extends Node
class_name shadow

var depth_texture : Texture2DRD

var rd : RenderingDevice

var fb_rid
var vertex_buffer
var vertex_count

var shader_rid : RID

@export var mesh_path: NodePath
var mesh_instance: MeshInstance3D

@export var camera_path: NodePath
var camera: Camera3D

@export var rect_path: NodePath
var rect: TextureRect

func _process(delta: float) -> void:
	var view_proj_matrix = _get_view_proj_matrix()
	_run_pipeline(view_proj_matrix, fb_rid, vertex_buffer, vertex_count)
	#_update_rect_display()

func _ready() -> void:
	_set_properties()
	
	rd = RenderingServer.get_rendering_device()
		
	var vert_code := FileAccess.get_file_as_bytes("res://shaders/shadow_vert.spv")
	var frag_code := FileAccess.get_file_as_bytes("res://shaders/shadow_frag.spv")

	var shader_spirv := RDShaderSPIRV.new()
	shader_spirv.bytecode_vertex = vert_code
	shader_spirv.bytecode_fragment = frag_code

	if shader_spirv.compile_error_vertex != "":
		print("Vertex shader error:\n", shader_spirv.compile_error_vertex)
	if shader_spirv.compile_error_fragment != "":
		print("Fragment shader error:\n", shader_spirv.compile_error_fragment)

	if shader_spirv.compile_error_vertex == "" and shader_spirv.compile_error_fragment == "":
		shader_rid = rd.shader_create_from_spirv(shader_spirv)
	else:
		push_error("Shader compilation failed!")
		return
	
	var texture_format := RDTextureFormat.new()
	#texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT # for a basic depth texture, for example
	texture_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	texture_format.width = 2048
	texture_format.height = 2048
	texture_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	)
	
	depth_texture = Texture2DRD.new()
	
	depth_texture.texture_rd_rid = rd.texture_create(texture_format, RDTextureView.new())
	
	fb_rid = rd.framebuffer_create([depth_texture.texture_rd_rid])
	
	var vertex_buffer_info := _get_vertex_buffer()
	vertex_buffer = vertex_buffer_info.vertex_buffer
	vertex_count = vertex_buffer_info.vertex_count
	
	var view_proj_matrix := _get_view_proj_matrix()
	
	debug_compare_vertex_projection()
	
	print(view_proj_matrix)
	
	_run_pipeline(view_proj_matrix, fb_rid, vertex_buffer, vertex_count)
	
	_update_rect_display()
	print("Shadow, online.")
	return
	
func _run_pipeline(view_proj_matrix: PackedByteArray, fb_rid: RID, vertex_buffer: RID, vertex_count: int) -> void:
	var uniform_buffer := rd.uniform_buffer_create(view_proj_matrix.size(), view_proj_matrix)

	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = 0
	uniform.add_id(uniform_buffer)

	var uniform_set := rd.uniform_set_create([uniform], shader_rid, 0)

	# Vertex format
	var vertex_attr := RDVertexAttribute.new()
	vertex_attr.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	vertex_attr.offset = 0
	vertex_attr.stride = 12
	vertex_attr.location = 0

	var vertex_format := rd.vertex_format_create([vertex_attr])
	var vertex_array_rid := rd.vertex_array_create(vertex_count, vertex_format, [vertex_buffer])

	# Pipeline state
	var raster := RDPipelineRasterizationState.new()
	raster.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED

	var depth := RDPipelineDepthStencilState.new()
	depth.enable_depth_test = true
	depth.enable_depth_write = true
	depth.depth_compare_operator = RenderingDevice.COMPARE_OP_LESS

	var msaa := RDPipelineMultisampleState.new()
	var blend := RDPipelineColorBlendState.new()
	var blend_attachment := RDPipelineColorBlendStateAttachment.new()
	blend_attachment.enable_blend = false
	blend.attachments = [blend_attachment]

	var format_rid := rd.framebuffer_get_format(fb_rid)

	var pipeline = rd.render_pipeline_create(shader_rid, format_rid, vertex_format, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, msaa, depth, blend)
	
	var clear_colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 1), Color(0, 0, 0, 1)])

	#var draw_list := rd.draw_list_begin(fb_rid, RenderingDevice.DRAW_IGNORE_ALL, clear_colors, 1.0, 0, Rect2(), 0)
	var draw_list := rd.draw_list_begin(fb_rid, RenderingDevice.DRAW_CLEAR_ALL, clear_colors, 1.0, 0, Rect2(), 0)

	rd.draw_list_bind_render_pipeline(draw_list, pipeline)
	rd.draw_list_bind_uniform_set(draw_list, uniform_set, 0)
	rd.draw_list_bind_vertex_array(draw_list, vertex_array_rid)

	rd.draw_list_draw(draw_list, false, 1)

	rd.draw_list_end()
	

func _update_rect_display():
	rect.texture =  depth_texture;
	
	print("Assigned texture RID:", depth_texture.texture_rd_rid)
	print("Texture width/height:", depth_texture.get_width(), depth_texture.get_height())
	print("Texture RID valid:", depth_texture.texture_rd_rid.is_valid())
	

	
	
func _get_view_proj_matrix() -> PackedByteArray:
	var view_mat := transform3d_to_mat4(camera.global_transform.affine_inverse())
	var proj_mat := projection_to_mat4(camera.get_camera_projection())

	var view_proj := mat4_mul(proj_mat, view_mat)
	
	return flatten_mat4_column_major(view_proj).to_byte_array()


func _get_vertex_buffer() -> Dictionary:
	var mesh = mesh_instance.mesh
	var vertex_array := PackedVector3Array()
	var indexed_vertices := PackedVector3Array()

	if mesh and mesh.get_surface_count() > 0:
		var arrays := mesh.surface_get_arrays(0)
		vertex_array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array

		if indices.size() > 0:
			for i in indices:
				indexed_vertices.append(vertex_array[i])
		else:
			indexed_vertices = vertex_array

	var float_array := PackedFloat32Array()
	for v in indexed_vertices:
		float_array.append_array([v.x, v.y, v.z])

	var byte_array = float_array.to_byte_array()
	var vertex_buffer = rd.vertex_buffer_create(float_array.size() * 4, byte_array)

	return {
		"vertex_buffer": vertex_buffer,
		"vertex_count": indexed_vertices.size()
	}
	
	

	return {
		"vertex_buffer": vertex_buffer,
		"vertex_count": vertex_array.size()
	}

func _set_properties():
	mesh_instance = get_node(mesh_path)
	camera = get_node(camera_path)
	rect = get_node(rect_path)
	
func transform3d_to_mat4(xform: Transform3D) -> Array:
	return [
		[xform.basis.x.x, xform.basis.y.x, xform.basis.z.x, xform.origin.x],
		[xform.basis.x.y, xform.basis.y.y, xform.basis.z.y, xform.origin.y],
		[xform.basis.x.z, xform.basis.y.z, xform.basis.z.z, xform.origin.z],
		[0.0,             0.0,             0.0,             1.0],
	]

func projection_to_mat4(p: Projection) -> Array:
	return [
		[p.x.x, p.y.x, p.z.x, p.w.x],
		[p.x.y, p.y.y, p.z.y, p.w.y],
		[p.x.z, p.y.z, p.z.z, p.w.z],
		[p.x.w, p.y.w, p.z.w, p.w.w]
	]
	
func mat4_mul(a: Array, b: Array) -> Array:
	var result := []
	for i in range(4):
		var row := []
		for j in range(4):
			var sum := 0.0
			for k in range(4):
				sum += a[i][k] * b[k][j]
			row.append(sum)
		result.append(row)
	return result
	
func flatten_mat4(m: Array) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for row in m:
		for val in row:
			arr.append(val)
	return arr
	
func flatten_mat4_column_major(m: Array) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for col in range(4):
		for row in range(4):
			arr.append(m[row][col])
	return arr

func debug_compare_vertex_projection():
	var cam := camera as Camera3D
	var view_proj := mat4_mul(projection_to_mat4(cam.get_camera_projection()), transform3d_to_mat4(cam.global_transform.affine_inverse()))
	
	var mesh := mesh_instance.mesh
	if not mesh or mesh.get_surface_count() == 0:
		return
	
	var vertices := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	
	for v in vertices:
		var v4 = [v.x, v.y, v.z, 1.0]
		
		# Multiply with matrix
		var projected := Vector4()
		for row in range(4):
			projected[row] = view_proj[row][0] * v4[0] + view_proj[row][1] * v4[1] + view_proj[row][2] * v4[2] + view_proj[row][3] * v4[3]
		
		# Perspective divide
		if projected.w != 0:
			projected /= projected.w
		
		# Godot's own screen projection (returns in pixels)
		var godot_proj := cam.unproject_position(v)
		
		var viewport_size = get_viewport().size
		var screen_uv = Vector2((projected.x + 1.0) * 0.5, (1.0 - (projected.y + 1.0) * 0.5))
		var screen_pos = screen_uv * Vector2(viewport_size)

		print("Custom screen pos: ", screen_pos, " | Godot: ", godot_proj)
