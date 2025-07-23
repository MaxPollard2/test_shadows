shader_type spatial;
render_mode unshaded;

global uniform sampler2D shadow_map;
global uniform mat4 shadow_view_proj;
global uniform vec3 light_pos;

varying vec3 world_position;

void vertex() {
    // Compute world-space position and pass it to the fragment shader
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Compute light direction and world normal
	vec3 light_dir = normalize(light_pos - world_position);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float light_amount = max(dot(light_dir, world_normal), 0.0);

	// Transform world position into shadow map space
	vec4 light_space_pos = shadow_view_proj * vec4(world_position, 1.0);
	vec3 shadow_coord = light_space_pos.xyz / light_space_pos.w;
	shadow_coord.xy = shadow_coord.xy * 0.5 + 0.5; // NDC → [0, 1]

	// Early discard if out of shadow map bounds


	// PCF settings
	float bias = max(0.000001 * (1.0 - dot(world_normal, light_dir)), 0.0000005);
	float shadow = 0.0;
	int samples = 4; // 4x4 grid
	float radius = 1.0 / 4096.0 * 2.0 * 0.2; // Adjust radius based on resolution

	// Percentage Closer Filtering (PCF)
	for (int x = -samples; x <= samples; x++) {
		for (int y = -samples; y <= samples; y++) {
			vec2 offset = vec2(float(x), float(y)) * radius;
			float sampled_depth = texture(shadow_map, shadow_coord.xy + offset).r;
			if (shadow_coord.z - bias > sampled_depth) {
				shadow += 1.0;
			}
		}
	}
	
	float total_samples = float((2 * samples + 1) * (2 * samples + 1));
	float shadow_factor = 1.0 - (shadow / total_samples); // 1.0 = lit, 0.0 = fully shadowed

	// Final shaded color
	vec3 base_color = vec3(0.255, 0.357, 0.451);
	ALBEDO = base_color * light_amount * shadow_factor;
	
	if (shadow_coord.x < 0.0 || shadow_coord.x > 1.0 ||
		shadow_coord.y < 0.0 || shadow_coord.y > 1.0) {
		ALBEDO = vec3(0.255, 0.357, 0.451) * light_amount;
	}
}
