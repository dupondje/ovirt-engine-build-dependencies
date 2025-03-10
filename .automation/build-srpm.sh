#!/bin/bash -xe

# Package version is static and should be aligned with engine version that is
# used to build maven cache
PKG_VERSION="4.5.7"

# Either a branch name or a specific tag in ovirt-engine project for which
# the maven cache is built
ENGINE_VERSION="master"

# Additional dependencies, which are going to be added to engine and which need
# to be included in ovirt-engine-build-dependencies, so proper build can pass
ADDITIONAL_DEPENDENCIES="
com.puppycrawl.tools:checkstyle:10.20.0
io.bit3:jsass:5.11.1
org.codehaus.mojo:gwt-maven-plugin:2.10.0
org.gwtproject:gwt:2.12.1:pom
org.gwtproject:gwt-user:2.12.1
org.gwtproject:gwt-dev:2.12.1
org.gwtproject:gwt-servlet:2.12.1
org.gwtproject:gwt-codeserver:2.12.1
"

# Directory, where build artifacts will be stored, should be passed as the 1st parameter
ARTIFACTS_DIR=${1:-exported-artifacts}

# Directory of the local maven repo
LOCAL_MAVEN_REPO="$(pwd)/repository"


[ -d ${LOCAL_MAVEN_REPO} ] || mkdir -p ${LOCAL_MAVEN_REPO}
[ -d ${ARTIFACTS_DIR} ] || mkdir -p ${ARTIFACTS_DIR}
[ -d rpmbuild/SOURCES ] || mkdir -p rpmbuild/SOURCES

# Fetch required engine version
git clone --depth=1 --branch=${ENGINE_VERSION} https://github.com/oVirt/ovirt-engine
cd ovirt-engine

# Mark current directory as safe for git to be able to execute git commands
git config --global --add safe.directory $(pwd)

# Prepare the release, which contain git hash of engine commit and current date
PKG_RELEASE="0.$(date +%04Y%02m%02d%02H%02M).git$(git rev-parse --short HEAD)"
#PKG_RELEASE="1"

# Set the location of the JDK that will be used for compilation:
export JAVA_HOME="${JAVA_HOME:=/usr/lib/jvm/java-11}"

# Build engine project to download all dependencies to the local maven repo
mvn \
    clean \
    install \
    -P gwt-admin \
    --no-transfer-progress \
    -Dgwt.userAgent=gecko1_8 \
    -Dgwt.compiler.localWorkers=1 \
    -Dgwt.jvmArgs='-Xms1G -Xmx3G' \
    -Dmaven.repo.local=${LOCAL_MAVEN_REPO}

# Install additional dependencies
for dep in ${ADDITIONAL_DEPENDENCIES} ; do
    mvn dependency:get -Dartifact=${dep} -Dmaven.repo.local=${LOCAL_MAVEN_REPO}
done

# Archive the fetched repository without artifacts produced as a part of engine build
cd ${LOCAL_MAVEN_REPO}/..

rm -rf repository/org/ovirt/engine/api/common-parent
rm -rf repository/org/ovirt/engine/api/interface
rm -rf repository/org/ovirt/engine/api/interface-common-jaxrs
rm -rf repository/org/ovirt/engine/api/restapi-apidoc
rm -rf repository/org/ovirt/engine/api/restapi-definition
rm -rf repository/org/ovirt/engine/api/restapi-jaxrs
rm -rf repository/org/ovirt/engine/api/restapi-parent
rm -rf repository/org/ovirt/engine/api/restapi-types
rm -rf repository/org/ovirt/engine/api/restapi-webapp
rm -rf repository/org/ovirt/engine/build-tools-root
rm -rf repository/org/ovirt/engine/checkstyles
rm -rf repository/org/ovirt/engine/core
rm -rf repository/org/ovirt/engine/engine-server-ear
rm -rf repository/org/ovirt/engine/extension
rm -rf repository/org/ovirt/engine/make
rm -rf repository/org/ovirt/engine/ovirt-checkstyle-extension
rm -rf repository/org/ovirt/engine/ovirt-findbugs-filters
rm -rf repository/org/ovirt/engine/root
rm -rf repository/org/ovirt/engine/ui

tar czf rpmbuild/SOURCES/ovirt-engine-build-dependencies-${PKG_VERSION}.tar.gz repository

# Set version and release
sed \
    -e "s|@VERSION@|${PKG_VERSION}|g" \
    -e "s|@RELEASE@|${PKG_RELEASE}|g" \
    < ovirt-engine-build-dependencies.spec.in \
    > ovirt-engine-build-dependencies.spec

# Build source package
rpmbuild \
    -D "_topdir rpmbuild" \
    -bs ovirt-engine-build-dependencies.spec
