package tengu

/*
Semantic version for the standalone tengu animation package.
*/

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

version_matches :: proc(major, minor, patch: int) -> bool {
	return (
		PACKAGE_VERSION.major == major &&
		PACKAGE_VERSION.minor == minor &&
		PACKAGE_VERSION.patch == patch
	)
}

version_at_least :: proc(major, minor, patch: int) -> bool {
	if PACKAGE_VERSION.major != major do return PACKAGE_VERSION.major > major
	if PACKAGE_VERSION.minor != minor do return PACKAGE_VERSION.minor > minor
	return PACKAGE_VERSION.patch >= patch
}
