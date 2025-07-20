#version 450

layout(location = 0) in vec3 a_position;

layout(std140, set = 0, binding = 0) uniform TransformData {
    mat4 view_proj;
};

void main() {
    //int idx = gl_VertexIndex;
    gl_Position = view_proj * vec4(a_position, 1.0);
}