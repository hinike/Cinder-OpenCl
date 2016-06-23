struct Particle {
	float4 pos;
	float4 vel;
	float4 col;
};

__kernel void  update( __global struct Particle *particles,
					  int		uFlockSize,
					  float		uDamping,
					  float		uZoneRadiusSqrd,
					  float		uRepelStrength,
					  float		uAlignStrength,
					  float		uAttractStrength,
					  float		uMinThresh,
					  float		uMaxThresh,
					  float		uTimeDelta)
{
	const float minSpeed = 0.00025f;
	const float maxSpeed = 1.0f;
	float3 acc = (float3) 0.0f;
	float3 newVel = (float3) 0.0f;
	float crowded = 1.0f;
	
	int index = get_global_id(0);
	
	float3 myPosition = particles[index].pos.xyz;
	float3 myVelocity = particles[index].vel.xyz;
	float3 col = float3( 0.2 );
	// Apply rules 1 and 2 for my member in the flock (based on all other
	// members)
	for( int i=0; i<uFlockSize; i++ ){
		if( i != index ) {
			//			if( crowded > 10.0 ) break;
			float3 theirPosition	= particles[i].pos.xyz;
			
			float3 dir			= myPosition - theirPosition;
			float distSqrd		= dir.x * dir.x + dir.y * dir.y + dir.z * dir.z;

			col = float3( 0.85f, 0.45f, 0 );

			if( distSqrd < uZoneRadiusSqrd - crowded * 0.01f ){
				float percent		= distSqrd/uZoneRadiusSqrd;
				float3 dirNorm		= normalize( dir );

				col = float3( 1, 1, 0 );

				// repulsion
				if( percent < uMinThresh ){
					float F			= ( uMinThresh/percent - 1.0f ) * uRepelStrength;
					acc				+= dirNorm * F * uTimeDelta;
					crowded			+= ( 1.0f - percent ) * 2.0f;

					col = float3( 1, 0, 0 );
				}
				else if( percent < uMaxThresh )
				{	// alignment
					float3 theirVelocity	= particles[i].vel.xyz;
					float threshDelta		= uMaxThresh - uMinThresh;
					float adjustedPercent	= ( percent - uMinThresh )/threshDelta;
					float F					= ( 1.0f - ( cos( adjustedPercent * 6.28318f ) * -0.5f + 0.5f ) ) * uAlignStrength;
					acc						+= normalize( theirVelocity ) * F * uTimeDelta;
					crowded					+= ( 1.0f - percent ) * 0.5f;

					col = float3( 0, 1, 0 );
				}
				else
				{	// attraction
					float threshDelta		= 1.0f - uMaxThresh;
					float adjustedPercent	= ( percent - uMaxThresh )/threshDelta;
					float F					= ( 1.0f - ( cos( adjustedPercent * 6.28318f ) * -0.5f + 0.5f ) ) * uAttractStrength;
					acc						-= dirNorm * F * uTimeDelta;
					crowded					+= ( 1.0f - percent ) * 0.25f;

					col = float3( 0, 0, 1 );
				}
			}
		}
	}
	
	// pull to center
	acc -= myPosition * 0.0015f;
	
	// Update position based on prior velocity and timestep
	float3 outPosition	= myPosition + myVelocity * uTimeDelta;
	
	// Update velocity based on calculated accelleration
	acc			= normalize( acc ) * min( length( acc ), 10.0f );
	newVel		= myVelocity * uDamping + acc * uTimeDelta;
	
	// Hard clamp speed (mag(velocity) to 10 to prevent insanity
	float newMaxSpeed = maxSpeed + crowded * 0.02f;
	float velLenSq = newVel.x * newVel.x + newVel.y * newVel.y + newVel.z * newVel.z;
	if( velLenSq > maxSpeed )
		newVel = normalize( newVel ) * newMaxSpeed;
	else if( velLenSq < minSpeed )
		newVel = normalize( newVel ) * minSpeed;
	
	
	float3 outVelocity = newVel;

	particles[index].pos.xyz = outPosition;
	particles[index].vel.xyz = outVelocity;

//	particles[index].col = float4( col, 1 ); // set color according to behavior
	particles[index].col = float4( 1, 0, 0, 1 ); // set all to red
}



__kernel void  smartUpdate( __global float4 *positions,
					  __global float4 *velocities,
					  int		uFlockSize,
					  float		uDamping,
					  float		uZoneRadiusSqrd,
					  float		uRepelStrength,
					  float		uAlignStrength,
					  float		uAttractStrength,
					  float		uMinThresh,
					  float		uMaxThresh,
					  float		uTimeDelta,
					__local float4* pBlock)
{
	const float minSpeed = 0.5f;
	const float maxSpeed = 1.0f;
	float3 acc = (float3) 0.0f;
	float3 newVel = (float3) 0.0f;
	float crowded = 1.0f;
	
	int globalIndex = get_global_id(0);
	int localIndex = get_local_id(0);
	
	int globalSize = get_global_size(0);
	int localSize = get_local_size(0);
	int totalBlocks = globalSize/localSize;
	
	float3 myPosition = positions[globalIndex].xyz;
	float3 myVelocity = velocities[globalIndex].xyz;
	// Apply rules 1 and 2 for my member in the flock (based on all other
	// members)
	for( int i = 0; i < totalBlocks; i++ ) {
		pBlock[localIndex] = positions[i*localSize+localIndex];
		barrier(CLK_LOCAL_MEM_FENCE);
		for( int j = 0; j < localSize; j++ ) {
			if( globalIndex == (i*localSize+j)) continue;
			float3 theirPosition = pBlock[j].xyz;
			float3 dir			= myPosition - theirPosition;
			float distSqrd		= dir.x * dir.x + dir.y * dir.y + dir.z * dir.z;
			
			if( distSqrd < uZoneRadiusSqrd - crowded * 0.01f ){
				float percent		= distSqrd/uZoneRadiusSqrd;
				float3 dirNorm		= normalize( dir );
				
				// repulsion
//				if( percent < uMinThresh ){
					float F			= ( uMinThresh/percent - 1.0f ) * uRepelStrength;
					acc				+= dirNorm * F * uTimeDelta;
					crowded			+= ( 1.0f - percent ) * 2.0f;
//				}
//				else if( percent < uMaxThresh )
//				{	// alignment
					float3 theirVelocity	= velocities[i*localSize+j].xyz;
					float threshDelta		= uMaxThresh - uMinThresh;
					float adjustedPercent	= ( percent - uMinThresh )/threshDelta;
					F					= ( 1.0f - ( cos( adjustedPercent * 6.28318f ) * -0.5f + 0.5f ) ) * uAlignStrength;
					acc						+= normalize( theirVelocity ) * F * uTimeDelta;
					crowded					+= ( 1.0f - percent ) * 0.5f;
//				}
//				else
//				{	// attraction
					threshDelta		= 1.0f - uMaxThresh;
					adjustedPercent	= ( percent - uMaxThresh )/threshDelta;
					F					= ( 1.0f - ( cos( adjustedPercent * 6.28318f ) * -0.5f + 0.5f ) ) * uAttractStrength;
					acc						-= dirNorm * F * uTimeDelta;
					crowded					+= ( 1.0f - percent ) * 0.25f;
//				}
			}

		}
		barrier(CLK_LOCAL_MEM_FENCE);
	}
	
	// pull to center
	acc -= myPosition * 0.0015f;
	
	// Update position based on prior velocity and timestep
	float3 outPosition	= myPosition + myVelocity * uTimeDelta;
	
	// Update velocity based on calculated accelleration
	acc			= normalize( acc ) * min( length( acc ), 10.0f );
	newVel		= myVelocity * uDamping + acc * uTimeDelta;
	
	// Hard clamp speed (mag(velocity) to 10 to prevent insanity
	float newMaxSpeed = maxSpeed + crowded * 0.02f;
	float velLenSq = newVel.x * newVel.x + newVel.y * newVel.y + newVel.z * newVel.z;
	if( velLenSq > maxSpeed )
		newVel = normalize( newVel ) * newMaxSpeed;
	else if( velLenSq < minSpeed )
		newVel = normalize( newVel ) * minSpeed;
	
	
	float3 outVelocity = newVel;
	
	positions[globalIndex].xyz = outPosition;
	velocities[globalIndex].xyz = outVelocity;

	
}