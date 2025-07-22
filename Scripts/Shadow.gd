#@tool
extends Node3D
class_name shadow

var rd: RenderingDevice
var shader_rid: RID
var pipeline: RID

var fb_rid: RID

var clear_colors: PackedColorArray

var color_texture: Texture2DRD
var depth_tex_rid: RID

var size = Vector2(4096, 4096)

var projection : Projection
var cached_view_proj : PackedByteArray

var view_proj_uniform_buffer: RID
var view_proj_uniform_set: RID

@export var rect_path: NodePath
@export var camera_path: NodePath

var mesh_instances: Array[ShadowMesh] = []

var rect: TextureRect


func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	
	var perspective = false
	
	var view = Projection(get_fixed_view_transform(global_transform))
	
	if perspective:
		projection = make_perspective_projection()
	else:
		projection = make_orthographic_projection()
		
	var camera = get_node(camera_path) as Camera3D
	print(camera.get_camera_projection())
	print(projection)
	
	
	var view_proj = projection * view
	cached_view_proj = flatten_projection_column_major(view_proj).to_byte_array()

	_load_shader()
	_create_render_target()
	_setup_pipeline()
	
	_run_pipeline(cached_view_proj)
	
	rect = get_node(rect_path)
	rect.texture =  color_texture;
	
	RenderingServer.global_shader_parameter_set("shadow_map", color_texture)
	
	get_tree().connect("node_added", Callable(self, "_on_node_added"))
	call_deferred("_register_existing_shadow_meshes")

	print("Shadow, online.")
	
	
	
	
func _process(delta: float) -> void:
	#look_at(Vector3(0,0,0));
	
	var view = Projection(get_fixed_view_transform(global_transform))
	var proj = projection
	var view_proj = proj * view
	

	
	cached_view_proj = flatten_projection_column_major(view_proj).to_byte_array()
	
	_run_pipeline(cached_view_proj)
	
	RenderingServer.global_shader_parameter_set("shadow_view_proj", view_proj)
	RenderingServer.global_shader_parameter_set("light_pos", global_position)
	
	#_debug()
	
func _debug():
	var view = Projection(get_fixed_view_transform(global_transform))
	var proj = make_orthographic_projection()
	var view_proj = proj * view
	
	var mesh_instance = mesh_instances[0].get_parent() as MeshInstance3D
	var mesh = mesh_instance.mesh as Mesh

	if mesh:
		var surface = mesh.surface_get_arrays(0) # surface 0
		var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	
		var model_matrix = mesh_instance.global_transform
		for i in range(min(3, vertices.size())):
			var local = vertices[i]
			var world = model_matrix * local
			var clip = view_proj * Vector4(world.x, world.y, world.z, 1.0)

			if clip.w != 0.0:
				var ndc = Vector3(clip.x, clip.y, clip.z) / clip.w
				print("Vertex", i, "→ NDC:", ndc)
			else:
				print("Vertex", i, "→ Invalid (w = 0)")
				
	var projection2 = make_perspective_projection()
	view_proj = projection2 * view
	
	if mesh:
		var surface = mesh.surface_get_arrays(0) # surface 0
		var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	
		var model_matrix = mesh_instance.global_transform
		for i in range(min(3, vertices.size())):
			var local = vertices[i]
			var world = model_matrix * local
			var clip = view_proj * Vector4(world.x, world.y, world.z, 1.0)

			if clip.w != 0.0:
				var ndc = Vector3(clip.x, clip.y, clip.z) / clip.w
				print("Vertex", i, "→ NDCperp:", ndc)
			else:
				print("Vertex", i, "→ Invalid (w = 0)")
	

func _run_pipeline(view_proj_matrix: PackedByteArray):
	rd.buffer_update(view_proj_uniform_buffer, 0, view_proj_matrix.size(), view_proj_matrix)

	var draw_list = rd.draw_list_begin(fb_rid, RenderingDevice.DRAW_CLEAR_ALL, clear_colors, 1.0, 0, Rect2(), 0)

	rd.draw_list_bind_render_pipeline(draw_list, pipeline)
	rd.draw_list_bind_uniform_set(draw_list, view_proj_uniform_set, 0)
	for i in range(mesh_instances.size()):
		rd.draw_list_bind_vertex_array(draw_list, mesh_instances[i].get_vertex_array_rid())
		rd.draw_list_bind_index_array(draw_list, mesh_instances[i].get_index_array_rid())
		rd.draw_list_bind_uniform_set(draw_list, mesh_instances[i].get_model_uniform_set(), 1)
		rd.draw_list_draw(draw_list, true, 1)
	rd.draw_list_end()
	
func _register_existing_shadow_meshes():
	for node in get_tree().get_nodes_in_group("shadow_meshes"):
		_register_shadow_caster(node)
	
func _on_node_added(node: Node):
	if node.is_in_group("shadow_meshes"):
		_register_shadow_caster(node)
		
func _register_shadow_caster(caster: ShadowMesh):
	caster.initialize(rd, shader_rid)
	mesh_instances.append(caster)

#func make_perspective_projection() -> Projection: # WORKING
	#var fov_deg = 75.0
	#var fov = deg_to_rad(fov_deg)
#
	#var near = 0.05
	#var far = 4000.0
	#
	#var aspect = size.x / size.y
	#var f = 1.0 / tan(fov / 2.0)
#
	#var x = Vector4(f / aspect, 0.0, 0.0, 0.0)
	#var y = Vector4(0.0, f, 0.0, 0.0)
	#var z = Vector4(0.0, 0.0, -(far + near) / (far - near), -1.0)
	#var w = Vector4(0.0, 0.0, -(2.0 * far * near) / (far - near), 0.0)
#
	#return Projection(x, y, z, w)
	
#func make_orthographic_projection() -> Projection:
	#var left = -5.0
	#var right = 5.0
	#var bottom = -5.0
	#var top = 5.0
	#var near = 0.05
	#var far = 4000.0
#
	#var rl = right - left
	#var tb = top - bottom
	#var fn = far - near
#
	#var x = Vector4(2.0 / rl, 0.0, 0.0, 0.0)
	#var y = Vector4(0.0, 2.0 / tb, 0.0, 0.0)
	#var z = Vector4(0.0, 0.0, -2.0 / fn, 0.0)
	#var w = Vector4(-(right + left) / rl, -(top + bottom) / tb, -(far + near) / fn, 1.0)
#
	#return Projection(x, y, z, w)
	
func make_perspective_projection() -> Projection:
	var fov_deg = 75.0
	var fov = deg_to_rad(fov_deg)

	var near = 0.05
	var far = 4000.0
	
	var aspect = size.x / size.y
	var f = 1.0 / tan(fov / 2.0)

	var x = Vector4(f / aspect, 0.0, 0.0, 0.0)
	var y = Vector4(0.0, f, 0.0, 0.0)
	var z = Vector4(0.0, 0.0, far / (far - near), 1.0)
	var w = Vector4(0.0, 0.0, -(far * near) / (far - near), 0.0)
	
	#z = Vector4(0.0, 0.0, -far / (far - near), -1.0)
	#w = Vector4(0.0, 0.0, (far * near) / (far - near), 0.0)

	return Projection(x, y, z, w)
	
func make_orthographic_projection() -> Projection:
	var left = -5.0
	var right = 5.0
	var bottom = -5.0
	var top = 5.0
	var near = 0.05
	var far = 4000.0

	var rl = right - left
	var tb = top - bottom
	var fn = far - near

	var x = Vector4(2.0 / rl, 0.0, 0.0, 0.0)
	var y = Vector4(0.0, 2.0 / tb, 0.0, 0.0)
	var z = Vector4(0.0, 0.0, 1.0 / fn, 0.0)
	var w = Vector4(-(right + left) / rl, -(top + bottom) / tb, -near / fn, 1.0)
	
	#z = Vector4(0.0, 0.0, -1.0 / fn, 0.0)
	#w = Vector4(0.0, 0.0, far / fn, 1.0)

	return Projection(x, y, z, w)
	
#func make_orthographic_projection() -> Projection:
	#var left = -5.0
	#var right = 5.0
	#var bottom = -5.0
	#var top = 5.0
	#var near = 0.05
	#var far = 4000.0
#
	#var rl = right - left
	#var tb = top - bottom
	#var fn = far - near
#
	#var x = Vector4(2.0 / rl, 0.0, 0.0, 0.0)
	#var y = Vector4(0.0, 2.0 / tb, 0.0, 0.0)
	##var z = Vector4(0.0, 0.0,  -2.0 / fn, 0.0)
	##var w = Vector4(0.0, 0.0,  -(far + near) / fn, 1.0)
	#var z = Vector4(0.0, 0.0, 1.0 / (far - near), 0.0)
	#var w = Vector4(0.0, 0.0, -near / (far - near), 1.0)
	#
#
	#return Projection(x, y, z, w)
	
#func make_perspective_projection() -> Projection:
	#var fov_deg = 75.0
	#var fov = deg_to_rad(fov_deg)
#
	#var near = 0.05
	#var far = 4000.0
	#
	#var aspect = size.x / size.y
	#var f = tan(fov / 2.0)
#
	#var x = Vector4(1 / (f * aspect), 0.0, 0.0, 0.0)
	#var y = Vector4(0.0, 1.0 / f, 0.0, 0.0)
	#var z = Vector4(0.0, 0.0, far / (far - near), 1.0)
	#var w = Vector4(0.0, 0.0, -(far * near) / (far - near), 0.0)
#
	#return Projection(x, y, z, w)
	#
#func make_orthographic_projection() -> Projection:
	#var left = -5.0
	#var right = 5.0
	#var bottom = -5.0
	#var top = 5.0
	#var near = 0.05
	#var far = 4000.0
#
	#var x = Vector4(2.0 / (right - left), 0.0, 0.0, 0.0)
	#var y = Vector4(0.0, 2.0 / (top - bottom), 0.0, 0.0)
	#var z = Vector4(0.0, 0.0, 1.0 / (far - near), 0.0)
	#var w = Vector4(-(right + left) / (right - left), -(top + bottom) / (top - bottom), -near / (far - near), 1.0)
#
	#return Projection(x, y, z, w)
	#
#func make_orthographic_projection() -> Projection:
	#var left = -5.0
	#var right = 5.0
	#var bottom = -5.0
	#var top = 5.0
	#var near = 0.05
	#var far = 4000.0
#
	#var rl = right - left
	#var tb = top - bottom
	#var fn = far - near
#
	#var x = Vector4(2.0 / rl, 0.0, 0.0, 0.0)
	#var y = Vector4(0.0, 2.0 / tb, 0.0, 0.0)
	#var z = Vector4(0.0, 0.0, 1.0 / fn, 0.0)
	#var w = Vector4(-(right + left) / rl, -(top + bottom) / tb, -near / fn, 1.0)
#
	#return Projection(x, y, z, w)

	
#func get_fixed_view_transform(xform : Transform3D) -> Transform3D:
	#xform.basis = xform.basis.orthonormalized()
#
	##if xform.basis.determinant() < 0: #enforce positive/negative determinant
		##xform.basis.x = -xform.basis.x
#
	#return xform.affine_inverse()
	
func get_fixed_view_transform(xform : Transform3D) -> Transform3D:
	xform.basis = xform.basis.orthonormalized()

	if xform.basis.determinant() < 0:
		xform.basis.x = -xform.basis.x

	# Flip Z to convert from OpenGL (RH) to Vulkan (LH), if needed:
	xform.basis.z = -xform.basis.z

	return xform.affine_inverse()


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
	color_format.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	color_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	
	color_format.width = size.x
	color_format.height = size.y

	var depth_format := RDTextureFormat.new()
	depth_format.format = RenderingDevice.DATA_FORMAT_D32_SFLOAT
	depth_format.usage_bits = RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
	depth_format.width = size.x
	depth_format.height = size.y

	var color_tex_rid := rd.texture_create(color_format, RDTextureView.new())
	var depth_tex_rid := rd.texture_create(depth_format, RDTextureView.new())
	
	color_texture.texture_rd_rid = color_tex_rid

	var color_attach := RDAttachmentFormat.new()
	color_attach.format = color_format.format
	color_attach.usage_flags = color_format.usage_bits

	var depth_attach := RDAttachmentFormat.new()
	depth_attach.format = depth_format.format
	depth_attach.usage_flags = depth_format.usage_bits

	var fb_format := rd.framebuffer_format_create([color_attach, depth_attach])

	var pass2 := RDFramebufferPass.new()
	pass2.color_attachments = [0]
	pass2.depth_attachment = 1

	fb_rid = rd.framebuffer_create_multipass([color_tex_rid, depth_tex_rid], [pass2], fb_format)
	

func _setup_pipeline():
	var vertex_attr = RDVertexAttribute.new()
	vertex_attr.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	vertex_attr.offset = 0
	vertex_attr.stride = 12
	vertex_attr.location = 0

	var vertex_format = rd.vertex_format_create([vertex_attr])

	var raster = RDPipelineRasterizationState.new()
	raster.cull_mode = RenderingDevice.POLYGON_CULL_FRONT

	var depth = RDPipelineDepthStencilState.new()
	depth.enable_depth_test = true
	depth.enable_depth_write = true
	depth.depth_compare_operator = RenderingDevice.COMPARE_OP_LESS
	#depth.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER

	var msaa = RDPipelineMultisampleState.new()
	var blend = RDPipelineColorBlendState.new()
	var blend_attachment = RDPipelineColorBlendStateAttachment.new()
	blend_attachment.enable_blend = false
	blend.attachments = [blend_attachment]

	var format_rid = rd.framebuffer_get_format(fb_rid)
	pipeline = rd.render_pipeline_create(shader_rid, format_rid, vertex_format, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, msaa, depth, blend)

	var view_proj_matrix = cached_view_proj
	view_proj_uniform_buffer = rd.uniform_buffer_create(view_proj_matrix.size(), view_proj_matrix)

	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = 0
	uniform.add_id(view_proj_uniform_buffer)

	view_proj_uniform_set = rd.uniform_set_create([uniform], shader_rid, 0)

	clear_colors = PackedColorArray([Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.5), Color(0, 0, 0, 1)])
	

func flatten_projection_column_major(p: Projection) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.append_array([p.x.x, p.x.y, p.x.z, p.x.w])
	arr.append_array([p.y.x, p.y.y, p.y.z, p.y.w])
	arr.append_array([p.z.x, p.z.y, p.z.z, p.z.w])
	arr.append_array([p.w.x, p.w.y, p.w.z, p.w.w])
	return arr

	
func _exit_tree():
	rd.free_rid(view_proj_uniform_buffer)
	rd.free_rid(view_proj_uniform_set)
	rd.free_rid(color_texture.texture_rd_rid)
	rd.free_rid(depth_tex_rid)
	rd.free_rid(fb_rid)
	rd.free_rid(pipeline)
