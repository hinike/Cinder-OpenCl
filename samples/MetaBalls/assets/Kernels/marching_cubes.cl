/*All source code is licensed under BSD
 
 Copyright (c) 2010, Daniel Holden All rights reserved.
 
 Corange is licensed under a basic BSD license.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

static int volume_coords(int3 coords, int3 size)
{
  return coords.x + coords.y * size.x + coords.z * size.x * size.y;
}

static int3 volume_position(int index, int3 size)
{
  return (int3)( index % size.x, (index / (size.x)) % size.y, index / (size.x * size.y) );
}

kernel void write_clear(global float* volume)
{
  volume[get_global_id(0)] = 0.0f;
}

static float smoothstepmap(float val)
{
  return val*val*(3 - 2*val);
}

struct Particle {
	float4 pos;
	float4 vel;
	float4 rand_life;
};

struct MarchingVert {
	float4 pos;
	float4 norm;
};

kernel void write_metaballs(global float* volume,
							global struct Particle* particles,
							int3 size,
							int num_metaballs )
{
	const int METABALL_SIZE = 1;
  
	int id = get_global_id(0);
  
	int3 pos = volume_position( id, size );
	int index = volume_coords( pos, size );
	
	float accumulation = 0.0f;
	
	for(int i = 0; i < num_metaballs; i++) {
		float3 metaball_pos = particles[i].pos.xyz;
		float dist = distance( (float3)(pos.x, pos.y, pos.z), metaball_pos ) / METABALL_SIZE;
		float amount = 1 - smoothstepmap( clamp( dist, 0.0f, 1.0f) );
		accumulation += amount;
	}
	
	volume[index] = accumulation;

}

// here, point_color is a pos and vol
kernel void write_point_color_back( global float* volume, global float4* pos_vol )
{
  float color = volume[get_global_id(0)];
  pos_vol[get_global_id(0)].w = color;
}

static float4 vertex_lerp(float threashold, float4 pos1, float4 pos2, float val1, float val2)
{
  float mu = (threashold - val1) / (val2 - val1);
  float4 ret = pos1 + mu * (pos2 - pos1);
  ret.w = 1;
  return ret;
}

#include "./kernels/lookup_table.cl"

kernel void construct_surface(global float* volume,
                              int3 volume_size,
                              global struct MarchingVert* vertex_buffer,
                              global int* vertex_index)
{
  int id = get_global_id(0);
  int3 pos = volume_position(id, volume_size);
  
  float v0 = volume[volume_coords(pos + (int3)(0,0,0), volume_size)];
  float v1 = volume[volume_coords(pos + (int3)(1,0,0), volume_size)];
  float v2 = volume[volume_coords(pos + (int3)(1,0,1), volume_size)];
  float v3 = volume[volume_coords(pos + (int3)(0,0,1), volume_size)];
  float v4 = volume[volume_coords(pos + (int3)(0,1,0), volume_size)];
  float v5 = volume[volume_coords(pos + (int3)(1,1,0), volume_size)];
  float v6 = volume[volume_coords(pos + (int3)(1,1,1), volume_size)];
  float v7 = volume[volume_coords(pos + (int3)(0,1,1), volume_size)];
  
  const float threashold = 0.5f;
  
  unsigned char c0 = v0 > threashold;
  unsigned char c1 = v1 > threashold;
  unsigned char c2 = v2 > threashold;
  unsigned char c3 = v3 > threashold;
  unsigned char c4 = v4 > threashold;
  unsigned char c5 = v5 > threashold;
  unsigned char c6 = v6 > threashold;
  unsigned char c7 = v7 > threashold;
  
  unsigned char hash = c0 | (c1 << 1) | (c2 << 2) | (c3 << 3) | (c4 << 4) | (c5 << 5) | (c6 << 6) | (c7 << 7);
  
  if ((hash == 0) || (hash == 255)) {
    return;
  }
  
  float4 p0 = (float4)(pos.x, pos.y, pos.z, 1) + (float4)(0,0,0, 0);
  float4 p1 = (float4)(pos.x, pos.y, pos.z, 1) + (float4)(1,0,0, 0);
  float4 p2 = (float4)(pos.x, pos.y, pos.z, 1) + (float4)(1,0,1, 0);
  float4 p3 = (float4)(pos.x, pos.y, pos.z, 1) + (float4)(0,0,1, 0);
  float4 p4 = (float4)(pos.x, pos.y, pos.z, 1) + (float4)(0,1,0, 0);
  float4 p5 = (float4)(pos.x, pos.y, pos.z, 1) + (float4)(1,1,0, 0);
  float4 p6 = (float4)(pos.x, pos.y, pos.z, 1) + (float4)(1,1,1, 0);
  float4 p7 = (float4)(pos.x, pos.y, pos.z, 1) + (float4)(0,1,1, 0);
  
  float4 vert_list[12];
  
  /* Find the vertices where the surface intersects the cube */
  
  vert_list[0] = vertex_lerp(threashold, p0, p1, v0, v1);
  vert_list[1] = vertex_lerp(threashold, p1, p2, v1, v2);
  vert_list[2] = vertex_lerp(threashold, p2, p3, v2, v3);
  vert_list[3] = vertex_lerp(threashold, p3, p0, v3, v0);
  vert_list[4] = vertex_lerp(threashold, p4, p5, v4, v5);
  vert_list[5] = vertex_lerp(threashold, p5, p6, v5, v6);
  vert_list[6] = vertex_lerp(threashold, p6, p7, v6, v7);
  vert_list[7] = vertex_lerp(threashold, p7, p4, v7, v4);
  vert_list[8] = vertex_lerp(threashold, p0, p4, v0, v4);
  vert_list[9] = vertex_lerp(threashold, p1, p5, v1, v5);
  vert_list[10] = vertex_lerp(threashold, p2, p6, v2, v6);
  vert_list[11] = vertex_lerp(threashold, p3, p7, v3, v7);
  
  /* Push appropriate verts to the back of the vertex buffer */
  
  int num_verts = triangle_counts[hash];
  int index = atomic_add(vertex_index, num_verts);
  
  for(int i = 0; i < num_verts; i++) {
    vertex_buffer[index + i].pos = vert_list[triangle_table[hash][i]];
  }
	
}

kernel void generate_flat_normals( global struct MarchingVert* vertex_buffer )
{
  int id = get_global_id(0);
  
  float4 pos1 = vertex_buffer[id * 3 + 0].pos;
  float4 pos2 = vertex_buffer[id * 3 + 1].pos;
  float4 pos3 = vertex_buffer[id * 3 + 2].pos;
  
  float3 pos12 = pos2.xyz - pos1.xyz;
  float3 pos13 = pos3.xyz - pos1.xyz;

  float3 normal = cross(pos12, pos13);
  normal = normalize(normal);
  
  vertex_buffer[id * 3 + 0].norm = (float4)(normal, 0);
  vertex_buffer[id * 3 + 1].norm = (float4)(normal, 0);
  vertex_buffer[id * 3 + 2].norm = (float4)(normal, 0);
}

kernel void generate_smooth_normals(global struct MarchingVert* vertex_buffer,
									global struct Particle* particles,
									int num_metaballs)
{  
	const float METABALL_SIZE = 1;
  
	int id = get_global_id(0);
	float3 vert_pos = vertex_buffer[id].pos.xyz;
  
	float3 normal = (float3)(0,0,0);
	for(int i = 0; i < num_metaballs; i++) {
		float3 particle_pos = particles[i].pos.xyz;
		float dist = distance(vert_pos, particle_pos) / METABALL_SIZE;
		float amount = 1-smoothstepmap( clamp(dist, 0.0f, 1.0f) );
		normal += (vert_pos - particle_pos) * amount;
	}
  
	normal = normalize(normal);
	vertex_buffer[id].norm = (float4)(normal, 0);
}
