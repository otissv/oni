package tengu

VERSION_MAJOR :: 1
VERSION_MINOR :: 0
VERSION_PATCH :: 0

VERSION_STRING :: "1.0.0"

API_Stability :: enum {
	STABLE,
}

API_STABILITY :: API_Stability.STABLE

Version :: struct {
	major: int,
	minor: int,
	patch: int,
}

PACKAGE_VERSION :: Version {
	major = VERSION_MAJOR,
	minor = VERSION_MINOR,
	patch = VERSION_PATCH,
}

version_string :: proc() -> string {
	return VERSION_STRING
}

version_matches :: proc(p: Version_Compare_Params) -> bool {
	return (
		PACKAGE_VERSION.major == p.major &&
		PACKAGE_VERSION.minor == p.minor &&
		PACKAGE_VERSION.patch == p.patch
	)
}

version_at_least :: proc(p: Version_Compare_Params) -> bool {
	if PACKAGE_VERSION.major != p.major do return PACKAGE_VERSION.major > p.major
	if PACKAGE_VERSION.minor != p.minor do return PACKAGE_VERSION.minor > p.minor
	return PACKAGE_VERSION.patch >= p.patch
}
