import { useCallback, useEffect, useRef } from 'react';
import { AccessibilityInfo, StyleSheet, View } from 'react-native';
import { ExpoWebGLRenderingContext, GLView } from 'expo-gl';

import type { FlightPhase } from '../motion/types';
import { gameColors } from './theme';

export type Atmosphere = FlightPhase | 'practice' | 'locker' | 'profile';

type ShaderPalette = {
  base: readonly [number, number, number];
  primary: readonly [number, number, number];
  secondary: readonly [number, number, number];
};

const palettes: Record<Atmosphere, ShaderPalette> = {
  idle: { base: [0.025, 0.03, 0.045], primary: [0.12, 0.2, 0.54], secondary: [0.24, 0.11, 0.35] },
  armed: { base: [0.03, 0.035, 0.07], primary: [0.24, 0.18, 0.62], secondary: [0.12, 0.32, 0.58] },
  airborne: { base: [0.07, 0.018, 0.025], primary: [0.72, 0.12, 0.08], secondary: [0.48, 0.08, 0.34] },
  settling: { base: [0.065, 0.028, 0.012], primary: [0.72, 0.22, 0.06], secondary: [0.42, 0.08, 0.28] },
  complete: { base: [0.025, 0.05, 0.02], primary: [0.42, 0.7, 0.08], secondary: [0.1, 0.38, 0.27] },
  practice: { base: [0.022, 0.03, 0.07], primary: [0.13, 0.28, 0.68], secondary: [0.38, 0.12, 0.52] },
  locker: { base: [0.045, 0.022, 0.07], primary: [0.34, 0.13, 0.58], secondary: [0.13, 0.29, 0.62] },
  profile: { base: [0.02, 0.042, 0.045], primary: [0.08, 0.32, 0.31], secondary: [0.22, 0.18, 0.5] },
};

const vertexSource = `
  attribute vec2 a_position;
  void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
  }
`;

const fragmentSource = `
  precision highp float;
  uniform vec2 u_resolution;
  uniform float u_time;
  uniform vec3 u_base;
  uniform vec3 u_primary;
  uniform vec3 u_secondary;

  float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
  }

  float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
      mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
      mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
      f.y
    );
  }

  float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
      value += amplitude * noise(p);
      p = p * 2.03 + vec2(4.7, 1.3);
      amplitude *= 0.5;
    }
    return value;
  }

  void main() {
    vec2 uv = gl_FragCoord.xy / max(u_resolution, vec2(1.0));
    vec2 p = uv - 0.5;
    p.x *= u_resolution.x / max(u_resolution.y, 1.0);
    float t = u_time * 0.065;
    float flow = fbm(p * 1.75 + vec2(t, -t * 0.42));
    float ribbon = sin(p.x * 2.8 + p.y * 1.7 + t * 2.1 + flow * 3.2) * 0.5 + 0.5;
    float bloom = smoothstep(0.18, 0.92, flow * 0.7 + ribbon * 0.3);
    vec3 color = mix(u_base, u_primary, bloom * 0.44);
    color = mix(color, u_secondary, smoothstep(0.7, 1.0, ribbon) * 0.2);
    float vignette = smoothstep(0.92, 0.18, length((uv - 0.5) * vec2(0.88, 1.0)));
    color *= 0.68 + vignette * 0.32;
    gl_FragColor = vec4(color, 1.0);
  }
`;

function compileShader(gl: ExpoWebGLRenderingContext, type: number, source: string) {
  const shader = gl.createShader(type);
  if (!shader) throw new Error('Unable to create shader');
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(shader) ?? 'Shader compilation failed');
  }
  return shader;
}

export function KineticBackdrop({
  atmosphere,
  onFps,
}: {
  atmosphere: Atmosphere;
  onFps?: (fps: number) => void;
}) {
  const atmosphereRef = useRef(atmosphere);
  const mountedRef = useRef(true);
  const onFpsRef = useRef(onFps);
  const reduceMotionRef = useRef(false);
  atmosphereRef.current = atmosphere;
  onFpsRef.current = onFps;

  useEffect(() => {
    AccessibilityInfo.isReduceMotionEnabled().then((enabled) => { reduceMotionRef.current = enabled; });
    const listener = AccessibilityInfo.addEventListener('reduceMotionChanged', (enabled) => {
      reduceMotionRef.current = enabled;
    });
    return () => listener.remove();
  }, []);

  useEffect(() => () => { mountedRef.current = false; }, []);

  const handleContextCreate = useCallback((gl: ExpoWebGLRenderingContext) => {
    const vertex = compileShader(gl, gl.VERTEX_SHADER, vertexSource);
    const fragment = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
    const program = gl.createProgram();
    if (!program) return;
    gl.attachShader(program, vertex);
    gl.attachShader(program, fragment);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;
    gl.useProgram(program);

    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const position = gl.getAttribLocation(program, 'a_position');
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);

    const resolution = gl.getUniformLocation(program, 'u_resolution');
    const time = gl.getUniformLocation(program, 'u_time');
    const base = gl.getUniformLocation(program, 'u_base');
    const primary = gl.getUniformLocation(program, 'u_primary');
    const secondary = gl.getUniformLocation(program, 'u_secondary');
    let animationFrame = 0;
    let lastDrawMs = 0;
    let fpsWindowMs = Date.now();
    let renderedFrames = 0;

    const render = (timestampMs: number) => {
      if (!mountedRef.current) {
        cancelAnimationFrame(animationFrame);
        gl.deleteBuffer(buffer);
        gl.deleteProgram(program);
        gl.deleteShader(vertex);
        gl.deleteShader(fragment);
        return;
      }

      if (timestampMs - lastDrawMs >= 32) {
        lastDrawMs = timestampMs;
        const palette = palettes[atmosphereRef.current];
        gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
        gl.uniform2f(resolution, gl.drawingBufferWidth, gl.drawingBufferHeight);
        gl.uniform1f(time, reduceMotionRef.current ? 2.5 : timestampMs / 1000);
        gl.uniform3f(base, ...palette.base);
        gl.uniform3f(primary, ...palette.primary);
        gl.uniform3f(secondary, ...palette.secondary);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        gl.flush();
        gl.endFrameEXP();
        renderedFrames += 1;
      }

      const now = Date.now();
      if (now - fpsWindowMs >= 1000) {
        onFpsRef.current?.(Math.round(renderedFrames * 1000 / (now - fpsWindowMs)));
        fpsWindowMs = now;
        renderedFrames = 0;
      }
      animationFrame = requestAnimationFrame(render);
    };
    animationFrame = requestAnimationFrame(render);
  }, []);

  return (
    <View pointerEvents="none" style={styles.shell}>
      <GLView msaaSamples={0} onContextCreate={handleContextCreate} style={StyleSheet.absoluteFillObject} />
    </View>
  );
}

const styles = StyleSheet.create({
  shell: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: gameColors.pitch,
  },
});
