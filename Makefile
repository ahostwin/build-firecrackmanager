# Build firecrackmanager in Docker: Linux amd64 binary, .deb, and SHA256SUMS -> ./dist
#
# Default source is ahostwin/firecrackmanager (Go module). The GitHub repo
# ahostwin/build-firecrackmanager is currently empty; override when it contains source:
#   make REPO_URL=https://github.com/ahostwin/build-firecrackmanager.git

IMAGE   ?= firecrackmanager-build:latest
REPO_URL ?= https://github.com/ahostwin/firecrackmanager.git
GIT_DEPTH ?= 100

.PHONY: all clean

all: dist
	docker build --platform linux/amd64 \
		--build-arg "REPO_URL=$(REPO_URL)" \
		--build-arg "GIT_DEPTH=$(GIT_DEPTH)" \
		-t "$(IMAGE)" \
		--target export \
		.
	docker run --rm -v "$(CURDIR)/dist:/dist" "$(IMAGE)"

dist:
	mkdir -p dist

clean:
	rm -rf dist
