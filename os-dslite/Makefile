PKG_NAME ?= os-dslite
# Leave empty by default; tools/build-pkg.sh auto-generates a timestamp version.
PKG_VERSION ?=
PKG_MAINTAINER ?= kawaii-not-kawaii@users.noreply.github.com
PKG_WWW ?= https://github.com/kawaii-not-kawaii/ds-lite-opnsense
PKG_ORIGIN ?= net/os-dslite

.PHONY: pkg clean

pkg:
	@PKG_NAME="${PKG_NAME}" \
	PKG_VERSION="${PKG_VERSION}" \
	PKG_MAINTAINER="${PKG_MAINTAINER}" \
	PKG_WWW="${PKG_WWW}" \
	PKG_ORIGIN="${PKG_ORIGIN}" \
	sh ./tools/build-pkg.sh

clean:
	rm -rf ./.pkgbuild ./dist
