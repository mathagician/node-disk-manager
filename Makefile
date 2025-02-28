# Copyright 2018-2019 The OpenEBS Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ==============================================================================
# Build Options

# set the shell to bash in case some environments use sh
SHELL:=/bin/bash

# VERSION is the version of the binary.
VERSION:=$(shell git describe --tags --always)

# Determine the arch/os
ifeq (${XC_OS}, )
  XC_OS:=$(shell go env GOOS)
endif
export XC_OS

ifeq (${XC_ARCH}, )
  XC_ARCH:=$(shell go env GOARCH)
endif
export XC_ARCH

ARCH:=${XC_OS}_${XC_ARCH}
export ARCH

ifeq (${BASE_DOCKER_IMAGEARM64}, )
  BASE_DOCKER_IMAGEARM64 = "arm64v8/ubuntu:18.04"
  export BASE_DOCKER_IMAGEARM64
endif

ifeq (${BASEIMAGE}, )
ifeq ($(ARCH),linux_arm64)
  BASEIMAGE:=${BASE_DOCKER_IMAGEARM64}
else
  # The ubuntu:16.04 image is being used as base image.
  BASEIMAGE:=ubuntu:16.04
endif
endif
export BASEIMAGE


# Initialize the NDM DaemonSet variables
# Specify the NDM DaemonSet binary name
NODE_DISK_MANAGER=ndm
# Specify the sub path under ./cmd/ for NDM DaemonSet
BUILD_PATH_NDM=ndm_daemonset
# Name of the image for NDM DaemoneSet
DOCKER_IMAGE_NDM:=openebs/node-disk-manager-${XC_ARCH}:ci

# Initialize the NDM Operator variables
# Specify the NDM Operator binary name
NODE_DISK_OPERATOR=ndo
# Specify the sub path under ./cmd/ for NDM Operator
BUILD_PATH_NDO=manager
# Name of the image for ndm operator
DOCKER_IMAGE_NDO:=openebs/node-disk-operator-${XC_ARCH}:ci

# Initialize the NDM Exporter variables
# Specfiy the NDM Exporter binary name
NODE_DISK_EXPORTER=exporter
# Specify the sub path under ./cmd/ for NDM Exporter
BUILD_PATH_EXPORTER=ndm-exporter
# Name of the image for ndm exporter
DOCKER_IMAGE_EXPORTER:=openebs/node-disk-exporter-${XC_ARCH}:ci

# Compile binaries and build docker images
.PHONY: build
build: clean build.common docker.ndm docker.ndo docker.exporter

.PHONY: build.common
.build.common: license-check-go version

# Tools required for different make targets or for development purposes
EXTERNAL_TOOLS=\
	github.com/golang/dep/cmd/dep \
	github.com/mitchellh/gox \
	gopkg.in/alecthomas/gometalinter.v1

# Bootstrap the build by downloading additional tools
.PHONY: bootstrap
bootstrap:
	@for tool in  $(EXTERNAL_TOOLS) ; do \
		echo "Installing $$tool" ; \
		go get -u $$tool; \
	done

.PHONY: header
header:
	@echo "----------------------------"
	@echo "--> node-disk-manager       "
	@echo "----------------------------"
	@echo

# -composite: avoid "literal copies lock value from fakePtr"
.PHONY: vet
vet:
	go list ./... | grep -v "./vendor/*" | xargs go vet -composites

.PHONY: fmt
fmt:
	find . -type f -name "*.go" | grep -v "./vendor/*" | xargs gofmt -s -w -l

# Run the bootstrap target once before trying gometalinter in Development environment
.PHONY: golint
golint:
	@gometalinter.v1 --install
	@gometalinter.v1 --vendor --deadline=600s ./...

# shellcheck target for checking shell scripts linting
.PHONY: shellcheck
shellcheck: getshellcheck
	find . -type f -name "*.sh" | grep -v "./vendor/*" | xargs /tmp/shellcheck-latest/shellcheck

.PHONY: getshellcheck
getshellcheck:
	wget -c 'https://goo.gl/ZzKHFv' --no-check-certificate -O - | tar -xvJ -C /tmp/

.PHONY: version
version:
	@echo $(VERSION)

.PHONY: test
test: 	vet fmt
	@echo "--> Running go test";
	$(PWD)/build/test.sh

.PHONY: integration-test
integration-test:
	go test -v -timeout 20m github.com/openebs/node-disk-manager/integration_tests/sanity

.PHONY: Dockerfile.ndm
Dockerfile.ndm: ./build/ndm-daemonset/Dockerfile.in
	sed -e 's|@BASEIMAGE@|$(BASEIMAGE)|g' $< >$@

.PHONY: Dockerfile.ndo
Dockerfile.ndo: ./build/ndm-operator/Dockerfile.in
	sed -e 's|@BASEIMAGE@|$(BASEIMAGE)|g' $< >$@

.PHONY: Dockerfile.exporter
Dockerfile.exporter: ./build/ndm-exporter/Dockerfile.in
	sed -e 's|@BASEIMAGE@|$(BASEIMAGE)|g' $< >$@

.PHONY: build.ndm
build.ndm:
	@echo '--> Building node-disk-manager binary...'
	@pwd
	@CTLNAME=${NODE_DISK_MANAGER} BUILDPATH=${BUILD_PATH_NDM} sh -c "'$(PWD)/build/build.sh'"
	@echo '--> Built binary.'
	@echo

.PHONY: docker.ndm
docker.ndm: build.ndm Dockerfile.ndm 
	@echo "--> Building docker image for ndm-daemonset..."
	@sudo docker build -t "$(DOCKER_IMAGE_NDM)" --build-arg ARCH=${ARCH} -f Dockerfile.ndm .
	@echo "--> Build docker image: $(DOCKER_IMAGE_NDM)"
	@echo

.PHONY: build.ndo
build.ndo:
	@echo '--> Building node-disk-operator binary...'
	@pwd
	@CTLNAME=${NODE_DISK_OPERATOR} BUILDPATH=${BUILD_PATH_NDO} sh -c "'$(PWD)/build/build.sh'"
	@echo '--> Built binary.'
	@echo

.PHONY: docker.ndo
docker.ndo: build.ndo Dockerfile.ndo 
	@echo "--> Building docker image for ndm-operator..."
	@sudo docker build -t "$(DOCKER_IMAGE_NDO)" --build-arg ARCH=${ARCH} -f Dockerfile.ndo .
	@echo "--> Build docker image: $(DOCKER_IMAGE_NDO)"
	@echo

.PHONY: build.exporter
build.exporter:
	@echo '--> Building node-disk-exporter binary...'
	@pwd
	@CTLNAME=${NODE_DISK_EXPORTER} BUILDPATH=${BUILD_PATH_EXPORTER} sh -c "'$(PWD)/build/build.sh'"
	@echo '--> Built binary.'
	@echo

.PHONY: docker.exporter
docker.exporter: build.exporter Dockerfile.exporter
	@echo "--> Building docker image for ndm-exporter..."
	@sudo docker build -t "$(DOCKER_IMAGE_EXPORTER)" --build-arg ARCH=${ARCH} -f Dockerfile.exporter .
	@echo "--> Build docker image: $(DOCKER_IMAGE_EXPORTER)"
	@echo

.PHONY: deps
deps: header
	@echo '--> Resolving dependencies...'
	dep ensure
	@echo '--> Depedencies resolved.'
	@echo

.PHONY: clean
clean: header
	@echo '--> Cleaning directory...'
	rm -rf bin
	rm -rf ${GOPATH}/bin/${NODE_DISK_MANAGER}
	rm -rf ${GOPATH}/bin/${NODE_DISK_OPERATOR}
	rm -rf ${GOPATH}/bin/${NODE_DISK_EXPORTER}
	rm -rf ${GOPATH}/pkg/*
	@echo '--> Done cleaning.'
	@echo

.PHONY: license-check-go
license-check-go:
	@echo "--> Checking license header..."
	@licRes=$$(for file in $$(find . -type f -iname '*.go' ! -path './vendor/*' ) ; do \
               awk 'NR<=3' $$file | grep -Eq "(Copyright|generated|GENERATED)" || echo $$file; \
       done); \
       if [ -n "$${licRes}" ]; then \
               echo "license header checking failed:"; echo "$${licRes}"; \
               exit 1; \
       fi
	@echo "--> Done checking license."
	@echo

.PHONY: push
push: 
	DIMAGE=openebs/node-disk-manager-${XC_ARCH} ./build/push;
	DIMAGE=openebs/node-disk-operator-${XC_ARCH} ./build/push;
	DIMAGE=openebs/node-disk-exporter-${XC_ARCH} ./build/push;
