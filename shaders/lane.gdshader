shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

uniform float CURVATURE = 2.0;
uniform float CURVATURE_DISTANCE = 110.0;
uniform vec3 line_color : source_color = vec3(0.86, 0.84, 0.72);
uniform bool dashed = false;
uniform float dash_len = 3.0;      // length of one dash + gap cycle
uniform float dash_fill = 0.45;    // painted fraction of the cycle
uniform float scroll_speed = 0.0;  // world units/sec the dashes flow toward the player

varying vec3 wpos;

void vertex() {
	wpos = VERTEX;
	float dist = length(INV_VIEW_MATRIX[3].xyz - VERTEX) / CURVATURE_DISTANCE;
	VERTEX.y -= pow(dist, CURVATURE);
}

void fragment() {
	if (dashed) {
		// scroll the dashes toward the player (+z) so they flow with the
		// world (obstacles/coins move toward +z at the same speed)
		float z = wpos.z - TIME * scroll_speed;
		float ph = fract(z / dash_len);
		if (ph > dash_fill) {
			discard;
		}
	}
	ALBEDO = line_color;
	EMISSION = line_color * 0.22;
	ROUGHNESS = 0.7;
}
