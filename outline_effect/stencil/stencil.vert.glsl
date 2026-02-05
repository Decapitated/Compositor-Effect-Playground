#version 450 core

layout(location = 0) in vec3 vertex_attribute;

void main()
{
    gl_Position = vec4(vertex_attribute, 1.0);
}