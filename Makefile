# Release pipeline for the cswap-connector binary.
#   make release-signed DEVELOPER_ID=<sha1> NOTARY_PROFILE=che-mcps-notary
# produces dist/cswap-connector (universal, Developer ID signed, notarized) and
# dist/cswap-connector.sha256. Publishing the GitHub Release is a separate step:
#   gh release create v<version> dist/cswap-connector dist/cswap-connector.sha256

NAME := cswap-connector
NOTARY_PROFILE ?= che-mcps-notary

.PHONY: test build-universal sign notarize checksum release-signed

test:
	swift test

build-universal:
	swift build -c release --arch arm64 --arch x86_64
	mkdir -p dist
	cp "$$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$(NAME)" dist/$(NAME)
	lipo -archs dist/$(NAME)

sign: build-universal
	@test -n "$(DEVELOPER_ID)" || { echo "DEVELOPER_ID is required" >&2; exit 2; }
	codesign --force --options runtime --timestamp --sign "$(DEVELOPER_ID)" dist/$(NAME)
	codesign --verify --deep --strict dist/$(NAME)

notarize: sign
	ditto -c -k --keepParent dist/$(NAME) dist/$(NAME).zip
	xcrun notarytool submit dist/$(NAME).zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	rm -f dist/$(NAME).zip

checksum:
	cd dist && shasum -a 256 $(NAME) > $(NAME).sha256 && cat $(NAME).sha256

release-signed: test notarize checksum
	spctl --assess --type install -vv dist/$(NAME)
