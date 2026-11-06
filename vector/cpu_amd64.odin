package oni_vector

import "core:sys/info"

@(private)
vector_cpu_has_avx2 :: #force_inline proc "contextless" () -> bool {
	return .avx2 in info.cpu_features()
}
