uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
  const vec2 blurStep = vec2(0.0045, 0.0075);
  vec4 color = texture2D(u_Tex0, v_TexCoord) * 0.24;

  color += texture2D(u_Tex0, v_TexCoord + vec2( blurStep.x, 0.0)) * 0.12;
  color += texture2D(u_Tex0, v_TexCoord + vec2(-blurStep.x, 0.0)) * 0.12;
  color += texture2D(u_Tex0, v_TexCoord + vec2(0.0,  blurStep.y)) * 0.12;
  color += texture2D(u_Tex0, v_TexCoord + vec2(0.0, -blurStep.y)) * 0.12;
  color += texture2D(u_Tex0, v_TexCoord + vec2( blurStep.x,  blurStep.y)) * 0.07;
  color += texture2D(u_Tex0, v_TexCoord + vec2(-blurStep.x,  blurStep.y)) * 0.07;
  color += texture2D(u_Tex0, v_TexCoord + vec2( blurStep.x, -blurStep.y)) * 0.07;
  color += texture2D(u_Tex0, v_TexCoord + vec2(-blurStep.x, -blurStep.y)) * 0.07;

  gl_FragColor = color;
}
