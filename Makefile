# Build firecrackmanager in Docker: Linux amd64 binary, .deb, and SHA256SUMS -> ./dist
#
# Default source is ahostwin/firecrackmanager (Go module). The GitHub repo
# ahostwin/build-firecrackmanager is currently empty; override when it contains source:
#   make REPO_URL=https://github.com/ahostwin/build-firecrackmanager.git

IMAGE   ?= firecrackmanager-build:latest
REPO_URL ?= https://github.com/ahostwin/firecrackmanager.git
GIT_DEPTH ?= 100

# Tip of remote default branch — changes when upstream moves so Docker reruns clone/go build, earlier layers stay cached.
SOURCE_REV ?= $(shell git ls-remote "$(REPO_URL)" HEAD 2>/dev/null | cut -f1)

.PHONY: all clean

all: dist
	@test -n "$(SOURCE_REV)" || (echo "SOURCE_REV is empty (git ls-remote failed?). Set SOURCE_REV=<full-sha> or fix REPO_URL/network." >&2; exit 1)
	DOCKER_BUILDKIT=1 docker build --platform linux/amd64 \
		--build-arg "REPO_URL=$(REPO_URL)" \
		--build-arg "GIT_DEPTH=$(GIT_DEPTH)" \
		--build-arg "SOURCE_REV=$(SOURCE_REV)" \
		-t "$(IMAGE)" \
		--target export \
		.
	docker run --rm -v "$(CURDIR)/dist:/dist" "$(IMAGE)"

dist:
	mkdir -p dist

clean:
	rm -rf dist
