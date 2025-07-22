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
	mat3 light_view_rot = mat3(shadow_view_proj); // Upper-left 3x3
	vec3 light_dir = normalize(light_pos - world_position);
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL.xyz, 0.0)).xyz;
	
	float light_amount = max(0.0, dot(light_dir, world_normal));
	
	ALBEDO = vec3(0.255, 0.357, 0.451) * light_amount;

    vec4 light_space_pos = shadow_view_proj * vec4(world_position, 1.0);

    vec3 shadow_coord = light_space_pos.xyz / light_space_pos.w;
    shadow_coord.xy = shadow_coord.xy * 0.5 + 0.5;

    float shadow_depth = texture(shadow_map, shadow_coord.xy).r;
    float current_depth = shadow_coord.z;
	
	float light = 1.0;

	// Check if UV is outside shadow map [0,1] range
	if (shadow_coord.x < 0.0 || shadow_coord.x > 1.0 ||
	    shadow_coord.y < 0.0 || shadow_coord.y > 1.0) {
	    // Outside of shadow map — assume fully lit
	    light = 1.0;
	} else {
	    float shadow_depth = texture(shadow_map, shadow_coord.xy).r;
	    float current_depth = shadow_coord.z;

	    if (current_depth - 0.00001 > shadow_depth) {
	        light = 0.0;
	    }
	}

	ALBEDO *= light;
}
