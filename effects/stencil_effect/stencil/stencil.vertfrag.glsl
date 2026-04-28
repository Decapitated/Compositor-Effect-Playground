#[vertex]
#version 450 core


layout(location = 0) in vec3 vertex_attribute;

void main()
{
    gl_Position = vec4(vertex_attribute, 1.0);
}

#[fragment]
#version 450 core

layout(push_constant, std430) uniform PushConstant {
    int stencil_ref;
} pc;

layout(location = 0) out float stencil;

void main() {
    stencil = pc.stencil_ref;
}
