extends Node
class_name shadow

var rd: RenderingDevice
var shader_rid: RID
var pipeline: RID

var fb_rid: RID
var vertex_buffer: RID
var vertex_array_rid: RID
var vertex_count: int

#var depth_texture: Texture2DRD
var clear_colors: PackedColorArray

var color_texture: Texture2DRD
var depth_tex_rid: RID
var fb_format_id: int

var view_proj_uniform_buffer: RID
var view_proj_uniform_set: RID

@export var mesh_path: NodePath
@export var camera_path: NodePath
@export var rect_path: NodePath

var mesh_instance: MeshInstance3D
var camera: Camera3D
var rect: TextureRect


func _ready() -> void:
	_set_properties()
	rd = RenderingServer.get_rendering_device()

	_load_shader()
	_create_render_target()
	_create_vertex_buffer()
	_setup_pipeline()
	
	_run_pipeline(_get_view_proj_matrix())
	_update_rect_display()

	print("Shadow, online.")
	
func _process(delta: float) -> void:
	var view_proj_matrix = _get_view_proj_matrix()
	_run_pipeline(view_proj_matrix)
	

func _run_pipeline(view_proj_matrix: PackedByteArray):
	rd.buffer_update(view_proj_uniform_buffer, 0, view_proj_matrix.size(), view_proj_matrix)

	var draw_list = rd.draw_list_begin(fb_rid, RenderingDevice.DRAW_CLEAR_ALL, clear_colors, 1.0, 0, Rect2(), 0)

	rd.draw_list_bind_render_pipeline(draw_list, pipeline)
	rd.draw_list_bind_uniform_set(draw_list, view_proj_uniform_set, 0)
	rd.draw_list_bind_vertex_array(draw_list, vertex_array_rid)
	rd.draw_list_draw(draw_list, false, 1)
	rd.draw_list_end()

func _load_shader():
	var vert_code = FileAccess.get_file_as_bytes("res://shaders/shadow_vert.spv")
	var frag_code = FileAccess.get_file_as_bytes("res://shaders/shadow_frag.spv")

	var shader_spirv = RDShaderSPIRV.new()
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
		
		
func _create_render_target():
	color_texture = Texture2DRD.new()

	var color_format := RDTextureFormat.new()
	color_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	color_format.width = 2048
	color_format.height = 2048
	color_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)

	var color_tex_rid := rd.texture_create(color_format, RDTextureView.new())
	color_texture.texture_rd_rid = color_tex_rid

	fb_rid = rd.framebuffer_create([color_tex_rid])


#func _create_render_target():
	#color_texture = Texture2DRD.new()
	#
	## Create color and depth texture formats
	#var color_format := RDTextureFormat.new()
	#color_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	#color_format.usage_bits = (
		#RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		#RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		#RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	#)
	#color_format.width = 2048
	#color_format.height = 2048
#
	#var depth_format := RDTextureFormat.new()
	#depth_format.format = RenderingDevice.DATA_FORMAT_D32_SFLOAT
	#depth_format.usage_bits = RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
	#depth_format.width = 2048
	#depth_format.height = 2048
#
	## Create textures
	#var color_tex_rid := rd.texture_create(color_format, RDTextureView.new())
	#var depth_tex_rid := rd.texture_create(depth_format, RDTextureView.new())
	#
	#color_texture.texture_rd_rid = color_tex_rid
#
	## Attachment formats
	#var color_attach := RDAttachmentFormat.new()
	#color_attach.format = color_format.format
	#color_attach.usage_flags = color_format.usage_bits
#
	#var depth_attach := RDAttachmentFormat.new()
	#depth_attach.format = depth_format.format
	#depth_attach.usage_flags = depth_format.usage_bits
#
	## Create framebuffer format
	#var fb_format := rd.framebuffer_format_create([color_attach, depth_attach])
#
	## Define pass and assign texture indices
	#var pass2 := RDFramebufferPass.new()
	#pass2.color_attachments = [0]              # 0 = color_tex_rid
	#pass2.depth_attachment = 1         # 1 = depth_tex_rid
#
	## Create framebuffer using multipass
	#fb_rid = rd.framebuffer_create_multipass([color_tex_rid, depth_tex_rid], [pass2], fb_format)
	

func _create_vertex_buffer():
	var mesh = mesh_instance.mesh
	if not mesh or mesh.get_surface_count() == 0:
		return

	var arrays = mesh.surface_get_arrays(0)
	var vertex_array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var indexed_vertices := PackedVector3Array()
	if indices.size() > 0:
		var temp_array := []
		for i in indices:
			temp_array.append(vertex_array[i])
		indexed_vertices = PackedVector3Array(temp_array)
	else:
		indexed_vertices = vertex_array

	var float_array = PackedFloat32Array()
	for v in indexed_vertices:
		float_array.append_array([v.x, v.y, v.z])

	var byte_array = float_array.to_byte_array()
	vertex_buffer = rd.vertex_buffer_create(float_array.size() * 4, byte_array)
	vertex_count = indexed_vertices.size()

func _setup_pipeline():
	var vertex_attr = RDVertexAttribute.new()
	vertex_attr.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	vertex_attr.offset = 0
	vertex_attr.stride = 12
	vertex_attr.location = 0

	var vertex_format = rd.vertex_format_create([vertex_attr])
	vertex_array_rid = rd.vertex_array_create(vertex_count, vertex_format, [vertex_buffer])

	var raster = RDPipelineRasterizationState.new()
	raster.cull_mode = RenderingDevice.POLYGON_CULL_BACK

	var depth = RDPipelineDepthStencilState.new()
	depth.enable_depth_test = true
	depth.enable_depth_write = true
	depth.depth_compare_operator = RenderingDevice.COMPARE_OP_LESS

	var msaa = RDPipelineMultisampleState.new()
	var blend = RDPipelineColorBlendState.new()
	var blend_attachment = RDPipelineColorBlendStateAttachment.new()
	blend_attachment.enable_blend = false
	blend.attachments = [blend_attachment]

	var format_rid = rd.framebuffer_get_format(fb_rid)
	pipeline = rd.render_pipeline_create(shader_rid, format_rid, vertex_format, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, msaa, depth, blend)

	var view_proj_matrix = _get_view_proj_matrix()
	view_proj_uniform_buffer = rd.uniform_buffer_create(view_proj_matrix.size(), view_proj_matrix)

	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = 0
	uniform.add_id(view_proj_uniform_buffer)

	view_proj_uniform_set = rd.uniform_set_create([uniform], shader_rid, 0)

	clear_colors = PackedColorArray([Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.5), Color(0, 0, 0, 1)])


func _update_rect_display():
	rect.texture =  color_texture;

func _set_properties():
	mesh_instance = get_node(mesh_path)
	camera = get_node(camera_path)
	rect = get_node(rect_path)


func _get_view_proj_matrix() -> PackedByteArray:
	var view_mat := transform3d_to_mat4(camera.global_transform.affine_inverse())
	var proj_mat := projection_to_mat4(camera.get_camera_projection())

	var view_proj := mat4_mul(proj_mat, view_mat)
	
	return flatten_mat4_column_major(view_proj).to_byte_array()


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


func flatten_mat4_column_major(m: Array) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for col in range(4):
		for row in range(4):
			arr.append(m[row][col])
	return arr
