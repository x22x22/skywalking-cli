#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

VERSION ?= latest
OUT_DIR = bin
BINARY = swctl

RELEASE_BIN = skywalking-cli-$(VERSION)-bin
RELEASE_SRC = skywalking-cli-$(VERSION)-src

OS = $(shell uname)

GO = go
GO_PATH = $$($(GO) env GOPATH)
GO_BUILD = $(GO) build
GO_GET = $(GO) get
GO_TEST = $(GO) test
GO_LINT = $(GO_PATH)/bin/golangci-lint
GO_LICENSER = $(GO_PATH)/bin/go-licenser
GO_PACKR = $(GO_PATH)/bin/packr2
GO_BUILD_FLAGS = -v
GO_BUILD_LDFLAGS = -X main.version=$(VERSION)
GQL_GEN = $(GO_PATH)/bin/gqlgen

PLATFORMS := windows linux darwin
os = $(word 1, $@)
ARCH = amd64

SHELL = /bin/bash

all: clean license deps codegen lint test build

tools:
	$(GO_PACKR) -v || go get -u github.com/gobuffalo/packr/v2/...
	$(GO_LINT) version || curl -sfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(GO_PATH)/bin v1.21.0
	$(GO_LICENSER) -version || GO111MODULE=off $(GO_GET) -u github.com/elastic/go-licenser
	$(GQL_GEN) version || go get -u github.com/99designs/gqlgen

deps: tools
	$(GO_GET) -v -t -d ./...

codegen: clean tools
	echo 'scalar Long' > query-protocol/schema.graphqls
	$(GQL_GEN) generate
	-rm -rf generated.go
	cd assets && GO111MODULE=on $(GO_PACKR) -v && cd ..

.PHONY: $(PLATFORMS)
$(PLATFORMS):
	mkdir -p $(OUT_DIR)
	GOOS=$(os) GOARCH=$(ARCH) $(GO_BUILD) $(GO_BUILD_FLAGS) -ldflags "$(GO_BUILD_LDFLAGS)" -o $(OUT_DIR)/$(BINARY)-$(VERSION)-$(os)-$(ARCH) cmd/main.go

.PHONY: lint
lint: codegen tools
	$(GO_LINT) run -v ./...

.PHONE: test
test: clean codegen lint
	$(GO_TEST) ./... -coverprofile=coverage.txt -covermode=atomic

.PHONY: build
build: deps windows linux darwin

.PHONY: license
license: clean tools
	$(GO_LICENSER) -d -licensor='Apache Software Foundation (ASF)' .

.PHONY: verify
verify: clean lint test license

.PHONY: fix
fix: tools
	$(GO_LINT) run -v --fix ./...
	$(GO_LICENSER) -licensor='Apache Software Foundation (ASF)' .

.PHONY: coverage
coverage: test
	bash <(curl -s https://codecov.io/bash) -t a5af28a3-92a2-4b35-9a77-54ad99b1ae00

.PHONY: clean
clean: tools
	-rm -rf bin
	-rm -rf coverage.txt
	-rm -rf query-protocol/schema.graphqls
	-rm -rf graphql/schema/schema.go
	-rm -rf *.tgz
	-rm -rf *.tgz
	-rm -rf *.asc
	-rm -rf *.sha512
	cd assets && $(GO_PACKR) clean

release-src: clean
	-tar -zcvf $(RELEASE_SRC).tgz \
	--exclude bin \
	--exclude .git \
	--exclude .idea \
	--exclude .DS_Store \
	--exclude .github \
	--exclude $(RELEASE_SRC).tgz \
	--exclude graphql/schema/schema.go \
	--exclude query-protocol/schema.graphqls \
	--exclude assets/packrd \
	--exclude assets/*-packr.go \
	.

release-bin: build
	-mkdir $(RELEASE_BIN)
	-cp -R bin $(RELEASE_BIN)
	-cp -R dist/* $(RELEASE_BIN)
	-cp -R CHANGES.md $(RELEASE_BIN)
	-cp -R README.md $(RELEASE_BIN)
	-tar -zcvf $(RELEASE_BIN).tgz $(RELEASE_BIN)
	-rm -rf $(RELEASE_BIN)

release: verify license release-src release-bin
	gpg --batch --yes --armor --detach-sig $(RELEASE_SRC).tgz
	shasum -a 512 $(RELEASE_SRC).tgz > $(RELEASE_SRC).tgz.sha512
	gpg --batch --yes --armor --detach-sig $(RELEASE_BIN).tgz
	shasum -a 512 $(RELEASE_BIN).tgz > $(RELEASE_BIN).tgz.sha512
