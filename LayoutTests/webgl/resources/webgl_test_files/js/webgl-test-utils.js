/*
Copyright (c) 2019 The Khronos Group Inc.
Use of this source code is governed by an MIT-style license that can be
found in the LICENSE.txt file.
*/
var WebGLTestUtils = (function() {
"use strict";

/**
 * Wrapped logging function.
 * @param {string} msg The message to log.
 */
var log = function(msg) {
  bufferedLogToConsole(msg);
};

/**
 * Wrapped logging function.
 * @param {string} msg The message to log.
 */
var error = function(msg) {
  // For the time being, diverting this to window.console.log rather
  // than window.console.error. If anyone cares enough they can
  // generalize the mechanism in js-test-pre.js.
  log(msg);
};

/**
 * Turn off all logging.
 */
var loggingOff = function() {
  log = function() {};
  error = function() {};
};

const ENUM_NAME_REGEX = RegExp('[A-Z][A-Z0-9_]*');
const ENUM_NAME_BY_VALUE = {};
const ENUM_NAME_PROTOTYPES = new Map();

/**
 * Converts a WebGL enum to a string.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} value The enum value.
 * @return {string} The enum as a string.
 */
var glEnumToString = function(glOrExt, value) {
  if (value === undefined)
    throw new Error('glEnumToString: `value` must not be undefined');

  const proto = glOrExt.__proto__;
  if (!ENUM_NAME_PROTOTYPES.has(proto)) {
    ENUM_NAME_PROTOTYPES.set(proto, true);

    for (const k in proto) {
      if (!ENUM_NAME_REGEX.test(k)) continue;

      const v = glOrExt[k];
      if (ENUM_NAME_BY_VALUE[v] === undefined) {
        ENUM_NAME_BY_VALUE[v] = k;
      } else {
        ENUM_NAME_BY_VALUE[v] += '/' + k;
      }
    }
  }

  const key = ENUM_NAME_BY_VALUE[value];
  if (key !== undefined) return key;

  return "0x" + Number(value).toString(16);
};

var lastError = "";

/**
 * Returns the last compiler/linker error.
 * @return {string} The last compiler/linker error.
 */
var getLastError = function() {
  return lastError;
};

/**
 * Whether a haystack ends with a needle.
 * @param {string} haystack String to search
 * @param {string} needle String to search for.
 * @param {boolean} True if haystack ends with needle.
 */
var endsWith = function(haystack, needle) {
  return haystack.substr(haystack.length - needle.length) === needle;
};

/**
 * Whether a haystack starts with a needle.
 * @param {string} haystack String to search
 * @param {string} needle String to search for.
 * @param {boolean} True if haystack starts with needle.
 */
var startsWith = function(haystack, needle) {
  return haystack.substr(0, needle.length) === needle;
};

/**
 * A vertex shader for a single texture.
 * @type {string}
 */
var simpleTextureVertexShader = [
  'attribute vec4 vPosition;',
  'attribute vec2 texCoord0;',
  'varying vec2 texCoord;',
  'void main() {',
  '    gl_Position = vPosition;',
  '    texCoord = texCoord0;',
  '}'].join('\n');

/**
 * A vertex shader for a single texture.
 * @type {string}
 */
var simpleTextureVertexShaderESSL300 = [
  '#version 300 es',
  'layout(location=0) in vec4 vPosition;',
  'layout(location=1) in vec2 texCoord0;',
  'out vec2 texCoord;',
  'void main() {',
  '    gl_Position = vPosition;',
  '    texCoord = texCoord0;',
  '}'].join('\n');

/**
 * A fragment shader for a single texture.
 * @type {string}
 */
var simpleTextureFragmentShader = [
  'precision mediump float;',
  'uniform sampler2D tex;',
  'varying vec2 texCoord;',
  'void main() {',
  '    gl_FragData[0] = texture2D(tex, texCoord);',
  '}'].join('\n');

/**
 * A fragment shader for a single texture.
 * @type {string}
 */
var simpleTextureFragmentShaderESSL300 = [
  '#version 300 es',
  'precision highp float;',
  'uniform highp sampler2D tex;',
  'in vec2 texCoord;',
  'out vec4 out_color;',
  'void main() {',
  '    out_color = texture(tex, texCoord);',
  '}'].join('\n');

/**
 * A fragment shader for a single texture with high precision.
 * @type {string}
 */
var simpleHighPrecisionTextureFragmentShader = [
  'precision highp float;',
  'uniform highp sampler2D tex;',
  'varying vec2 texCoord;',
  'void main() {',
  '    gl_FragData[0] = texture2D(tex, texCoord);',
  '}'].join('\n');

/**
 * A fragment shader for a single cube map texture.
 * @type {string}
 */
var simpleCubeMapTextureFragmentShader = [
  'precision mediump float;',
  'uniform samplerCube tex;',
  'uniform highp int face;',
  'varying vec2 texCoord;',
  'void main() {',
  // Transform [0, 1] -> [-1, 1]
  '    vec2 texC2 = (texCoord * 2.) - 1.;',
  // Transform 2d tex coord. to each face of TEXTURE_CUBE_MAP coord.
  '    vec3 texCube = vec3(0., 0., 0.);',
  '    if (face == 34069) {',         // TEXTURE_CUBE_MAP_POSITIVE_X
  '        texCube = vec3(1., -texC2.y, -texC2.x);',
  '    } else if (face == 34070) {',  // TEXTURE_CUBE_MAP_NEGATIVE_X
  '        texCube = vec3(-1., -texC2.y, texC2.x);',
  '    } else if (face == 34071) {',  // TEXTURE_CUBE_MAP_POSITIVE_Y
  '        texCube = vec3(texC2.x, 1., texC2.y);',
  '    } else if (face == 34072) {',  // TEXTURE_CUBE_MAP_NEGATIVE_Y
  '        texCube = vec3(texC2.x, -1., -texC2.y);',
  '    } else if (face == 34073) {',  // TEXTURE_CUBE_MAP_POSITIVE_Z
  '        texCube = vec3(texC2.x, -texC2.y, 1.);',
  '    } else if (face == 34074) {',  // TEXTURE_CUBE_MAP_NEGATIVE_Z
  '        texCube = vec3(-texC2.x, -texC2.y, -1.);',
  '    }',
  '    gl_FragData[0] = textureCube(tex, texCube);',
  '}'].join('\n');

/**
 * A vertex shader for a single texture.
 * @type {string}
 */
var noTexCoordTextureVertexShader = [
  'attribute vec4 vPosition;',
  'varying vec2 texCoord;',
  'void main() {',
  '    gl_Position = vPosition;',
  '    texCoord = vPosition.xy * 0.5 + 0.5;',
  '}'].join('\n');

/**
 * A vertex shader for a uniform color.
 * @type {string}
 */
var simpleVertexShader = [
  'attribute vec4 vPosition;',
  'void main() {',
  '    gl_Position = vPosition;',
  '}'].join('\n');

/**
 * A vertex shader for a uniform color.
 * @type {string}
 */
var simpleVertexShaderESSL300 = [
  '#version 300 es',
  'in vec4 vPosition;',
  'void main() {',
  '    gl_Position = vPosition;',
  '}'].join('\n');

/**
 * A fragment shader for a uniform color.
 * @type {string}
 */
var simpleColorFragmentShader = [
  'precision mediump float;',
  'uniform vec4 u_color;',
  'void main() {',
  '    gl_FragData[0] = u_color;',
  '}'].join('\n');

/**
 * A fragment shader for a uniform color.
 * @type {string}
 */
var simpleColorFragmentShaderESSL300 = [
  '#version 300 es',
  'precision mediump float;',
  'out vec4 out_color;',
  'uniform vec4 u_color;',
  'void main() {',
  '    out_color = u_color;',
  '}'].join('\n');

/**
 * A vertex shader for vertex colors.
 * @type {string}
 */
var simpleVertexColorVertexShader = [
  'attribute vec4 vPosition;',
  'attribute vec4 a_color;',
  'varying vec4 v_color;',
  'void main() {',
  '    gl_Position = vPosition;',
  '    v_color = a_color;',
  '}'].join('\n');

/**
 * A fragment shader for vertex colors.
 * @type {string}
 */
var simpleVertexColorFragmentShader = [
  'precision mediump float;',
  'varying vec4 v_color;',
  'void main() {',
  '    gl_FragData[0] = v_color;',
  '}'].join('\n');

/**
 * Creates a program, attaches shaders, binds attrib locations, links the
 * program and calls useProgram.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Array.<!WebGLShader|string>} shaders The shaders to
 *        attach, or the source, or the id of a script to get
 *        the source from.
 * @param {!Array.<string>} opt_attribs The attribs names.
 * @param {!Array.<number>} opt_locations The locations for the attribs.
 * @param {boolean} opt_logShaders Whether to log shader source.
 */
var setupProgram = function(
    gl, shaders, opt_attribs, opt_locations, opt_logShaders) {
  var realShaders = [];
  var program = gl.createProgram();
  var shaderCount = 0;
  for (var ii = 0; ii < shaders.length; ++ii) {
    var shader = shaders[ii];
    var shaderType = undefined;
    if (typeof shader == 'string') {
      const element = shader != '' && document.getElementById(shader);
      if (element) {
        if (element.type != "x-shader/x-vertex" && element.type != "x-shader/x-fragment")
          shaderType = ii ? gl.FRAGMENT_SHADER : gl.VERTEX_SHADER;
        shader = loadShaderFromScript(gl, shader, shaderType, undefined, opt_logShaders);
      } else if (endsWith(shader, ".vert")) {
        shader = loadShaderFromFile(gl, shader, gl.VERTEX_SHADER, undefined, opt_logShaders);
      } else if (endsWith(shader, ".frag")) {
        shader = loadShaderFromFile(gl, shader, gl.FRAGMENT_SHADER, undefined, opt_logShaders);
      } else {
        shader = loadShader(gl, shader, ii ? gl.FRAGMENT_SHADER : gl.VERTEX_SHADER, undefined, opt_logShaders);
      }
    } else if (opt_logShaders) {
      throw 'Shader source logging requested but no shader source provided';
    }
    if (shader) {
      ++shaderCount;
      gl.attachShader(program, shader);
    }
  }
  if (shaderCount != 2) {
    error("Error in compiling shader");
    return null;
  }
  if (opt_attribs) {
    for (var ii = 0; ii < opt_attribs.length; ++ii) {
      gl.bindAttribLocation(
          program,
          opt_locations ? opt_locations[ii] : ii,
          opt_attribs[ii]);
    }
  }
  gl.linkProgram(program);

  // Check the link status
  var linked = gl.getProgramParameter(program, gl.LINK_STATUS);
  if (!linked) {
      // something went wrong with the link
      lastError = gl.getProgramInfoLog (program);
      error("Error in program linking:" + lastError);

      gl.deleteProgram(program);
      return null;
  }

  gl.useProgram(program);
  return program;
};

/**
 * Creates a program, attaches shader, sets up trasnform feedback varyings,
 * binds attrib locations, links the program and calls useProgram.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Array.<!WebGLShader|string>} shaders The shaders to
 *        attach, or the source, or the id of a script to get
 *        the source from.
 * @param {!Array.<string>} varyings The transform feedback varying names.
 * @param {number} bufferMode The mode used to capture the varying variables.
 * @param {!Array.<string>} opt_attribs The attribs names.
 * @param {!Array.<number>} opt_locations The locations for the attribs.
 * @param {boolean} opt_logShaders Whether to log shader source.
 */
var setupTransformFeedbackProgram = function(
    gl, shaders, varyings, bufferMode, opt_attribs, opt_locations, opt_logShaders, opt_skipCompileStatus) {
  var realShaders = [];
  var program = gl.createProgram();
  var shaderCount = 0;
  for (var ii = 0; ii < shaders.length; ++ii) {
    var shader = shaders[ii];
    var shaderType = undefined;
    if (typeof shader == 'string') {
      var element = document.getElementById(shader);
      if (element) {
        if (element.type != "x-shader/x-vertex" && element.type != "x-shader/x-fragment")
          shaderType = ii ? gl.FRAGMENT_SHADER : gl.VERTEX_SHADER;
        shader = loadShaderFromScript(gl, shader, shaderType, undefined, opt_logShaders, opt_skipCompileStatus);
      } else if (endsWith(shader, ".vert")) {
        shader = loadShaderFromFile(gl, shader, gl.VERTEX_SHADER, undefined, opt_logShaders, opt_skipCompileStatus);
      } else if (endsWith(shader, ".frag")) {
        shader = loadShaderFromFile(gl, shader, gl.FRAGMENT_SHADER, undefined, opt_logShaders, opt_skipCompileStatus);
      } else {
        shader = loadShader(gl, shader, ii ? gl.FRAGMENT_SHADER : gl.VERTEX_SHADER, undefined, opt_logShaders, undefined, undefined, opt_skipCompileStatus);
      }
    } else if (opt_logShaders) {
      throw 'Shader source logging requested but no shader source provided';
    }
    if (shader) {
      ++shaderCount;
      gl.attachShader(program, shader);
    }
  }
  if (shaderCount != 2) {
    error("Error in compiling shader");
    return null;
  }

  if (opt_attribs) {
    for (var ii = 0; ii < opt_attribs.length; ++ii) {
      gl.bindAttribLocation(
          program,
          opt_locations ? opt_locations[ii] : ii,
          opt_attribs[ii]);
    }
  }

  gl.transformFeedbackVaryings(program, varyings, bufferMode);

  gl.linkProgram(program);

  // Check the link status
  var linked = gl.getProgramParameter(program, gl.LINK_STATUS);
  if (!linked) {
      // something went wrong with the link
      lastError = gl.getProgramInfoLog (program);
      error("Error in program linking:" + lastError);

      gl.deleteProgram(program);
      return null;
  }

  gl.useProgram(program);
  return program;
};

/**
 * Creates a simple texture program.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @return {WebGLProgram}
 */
var setupNoTexCoordTextureProgram = function(gl) {
  return setupProgram(gl,
                      [noTexCoordTextureVertexShader, simpleTextureFragmentShader],
                      ['vPosition'],
                      [0]);
};

/**
 * Creates a simple texture program.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} opt_positionLocation The attrib location for position.
 * @param {number} opt_texcoordLocation The attrib location for texture coords.
 * @param {string} opt_fragmentShaderOverride The alternative fragment shader to use.
 * @return {WebGLProgram}
 */
var setupSimpleTextureProgram = function(
    gl, opt_positionLocation, opt_texcoordLocation, opt_fragmentShaderOverride) {
  opt_positionLocation = opt_positionLocation || 0;
  opt_texcoordLocation = opt_texcoordLocation || 1;
  opt_fragmentShaderOverride = opt_fragmentShaderOverride || simpleTextureFragmentShader;
  return setupProgram(gl,
                      [simpleTextureVertexShader, opt_fragmentShaderOverride],
                      ['vPosition', 'texCoord0'],
                      [opt_positionLocation, opt_texcoordLocation]);
};

/**
 * Creates a simple texture program using glsl version 300.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} opt_positionLocation The attrib location for position.
 * @param {number} opt_texcoordLocation The attrib location for texture coords.
 * @param {string} opt_fragmentShaderOverride The alternative fragment shader to use.
 * @return {WebGLProgram}
 */
var setupSimpleTextureProgramESSL300 = function(
    gl, opt_positionLocation, opt_texcoordLocation, opt_fragmentShaderOverride) {
  opt_positionLocation = opt_positionLocation || 0;
  opt_texcoordLocation = opt_texcoordLocation || 1;
  opt_fragmentShaderOverride = opt_fragmentShaderOverride || simpleTextureFragmentShaderESSL300;
  return setupProgram(gl,
                      [simpleTextureVertexShaderESSL300, opt_fragmentShaderOverride],
                      ['vPosition', 'texCoord0'],
                      [opt_positionLocation, opt_texcoordLocation]);
};

/**
 * Creates a simple cube map texture program.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} opt_positionLocation The attrib location for position.
 * @param {number} opt_texcoordLocation The attrib location for texture coords.
 * @return {WebGLProgram}
 */
var setupSimpleCubeMapTextureProgram = function(
    gl, opt_positionLocation, opt_texcoordLocation) {
  opt_positionLocation = opt_positionLocation || 0;
  opt_texcoordLocation = opt_texcoordLocation || 1;
  return setupProgram(gl,
                      [simpleTextureVertexShader, simpleCubeMapTextureFragmentShader],
                      ['vPosition', 'texCoord0'],
                      [opt_positionLocation, opt_texcoordLocation]);
};

/**
 * Creates a simple vertex color program.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} opt_positionLocation The attrib location for position.
 * @param {number} opt_vertexColorLocation The attrib location
 *        for vertex colors.
 * @return {WebGLProgram}
 */
var setupSimpleVertexColorProgram = function(
    gl, opt_positionLocation, opt_vertexColorLocation) {
  opt_positionLocation = opt_positionLocation || 0;
  opt_vertexColorLocation = opt_vertexColorLocation || 1;
  return setupProgram(gl,
                      [simpleVertexColorVertexShader, simpleVertexColorFragmentShader],
                      ['vPosition', 'a_color'],
                      [opt_positionLocation, opt_vertexColorLocation]);
};

/**
 * Creates a simple color program.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} opt_positionLocation The attrib location for position.
 * @return {WebGLProgram}
 */
var setupSimpleColorProgram = function(gl, opt_positionLocation) {
  opt_positionLocation = opt_positionLocation || 0;
  return setupProgram(gl,
                      [simpleVertexShader, simpleColorFragmentShader],
                      ['vPosition'],
                      [opt_positionLocation]);
};

/**
 * Creates buffers for a textured unit quad and attaches them to vertex attribs.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} opt_positionLocation The attrib location for position.
 * @param {number} opt_texcoordLocation The attrib location for texture coords.
 * @param {!Object} various options. See setupQuad for details.
 * @return {!Array.<WebGLBuffer>} The buffer objects that were
 *      created.
 */
var setupUnitQuad = function(gl, opt_positionLocation, opt_texcoordLocation, options) {
  return setupQuadWithTexCoords(gl, [ 0.0, 0.0 ], [ 1.0, 1.0 ],
                                opt_positionLocation, opt_texcoordLocation,
                                options);
};

/**
 * Creates buffers for a textured quad with specified lower left
 * and upper right texture coordinates, and attaches them to vertex
 * attribs.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Array.<number>} lowerLeftTexCoords The texture coordinates for the lower left corner.
 * @param {!Array.<number>} upperRightTexCoords The texture coordinates for the upper right corner.
 * @param {number} opt_positionLocation The attrib location for position.
 * @param {number} opt_texcoordLocation The attrib location for texture coords.
 * @param {!Object} various options. See setupQuad for details.
 * @return {!Array.<WebGLBuffer>} The buffer objects that were
 *      created.
 */
var setupQuadWithTexCoords = function(
    gl, lowerLeftTexCoords, upperRightTexCoords,
    opt_positionLocation, opt_texcoordLocation, options) {
  var defaultOptions = {
    positionLocation: opt_positionLocation || 0,
    texcoordLocation: opt_texcoordLocation || 1,
    lowerLeftTexCoords: lowerLeftTexCoords,
    upperRightTexCoords: upperRightTexCoords
  };
  if (options) {
    for (var prop in options) {
      defaultOptions[prop] = options[prop]
    }
  }
  return setupQuad(gl, defaultOptions);
};

/**
 * Makes a quad with various options.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Object} options
 *
 * scale: scale to multiply unit quad values by. default 1.0.
 * positionLocation: attribute location for position.
 * texcoordLocation: attribute location for texcoords.
 *     If this does not exist no texture coords are created.
 * lowerLeftTexCoords: an array of 2 values for the
 *     lowerLeftTexCoords.
 * upperRightTexCoords: an array of 2 values for the
 *     upperRightTexCoords.
 */
var setupQuad = function(gl, options) {
  var positionLocation = options.positionLocation || 0;
  var scale = options.scale || 1;

  var objects = [];

  var vertexObject = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, vertexObject);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([
       1.0 * scale ,  1.0 * scale,
      -1.0 * scale ,  1.0 * scale,
      -1.0 * scale , -1.0 * scale,
       1.0 * scale ,  1.0 * scale,
      -1.0 * scale , -1.0 * scale,
       1.0 * scale , -1.0 * scale]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(positionLocation);
  gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);
  objects.push(vertexObject);

  if (options.texcoordLocation !== undefined) {
    var llx = options.lowerLeftTexCoords[0];
    var lly = options.lowerLeftTexCoords[1];
    var urx = options.upperRightTexCoords[0];
    var ury = options.upperRightTexCoords[1];

    vertexObject = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, vertexObject);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([
        urx, ury,
        llx, ury,
        llx, lly,
        urx, ury,
        llx, lly,
        urx, lly]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(options.texcoordLocation);
    gl.vertexAttribPointer(options.texcoordLocation, 2, gl.FLOAT, false, 0, 0);
    objects.push(vertexObject);
  }

  return objects;
};

/**
 * Creates a program and buffers for rendering a textured quad.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} opt_positionLocation The attrib location for
 *        position. Default = 0.
 * @param {number} opt_texcoordLocation The attrib location for
 *        texture coords. Default = 1.
 * @param {!Object} various options defined by setupQuad, plus an option
          fragmentShaderOverride to specify a custom fragment shader.
 * @return {!WebGLProgram}
 */
var setupTexturedQuad = function(
    gl, opt_positionLocation, opt_texcoordLocation, options) {
  var program = setupSimpleTextureProgram(
      gl, opt_positionLocation, opt_texcoordLocation, options && options.fragmentShaderOverride);
  setupUnitQuad(gl, opt_positionLocation, opt_texcoordLocation, options);
  return program;
};

/**
 * Creates a program and buffers for rendering a color quad.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} opt_positionLocation The attrib location for position.
 * @param {!Object} various options. See setupQuad for details.
 * @return {!WebGLProgram}
 */
var setupColorQuad = function(gl, opt_positionLocation, options) {
  opt_positionLocation = opt_positionLocation || 0;
  var program = setupSimpleColorProgram(gl, opt_positionLocation);
  setupUnitQuad(gl, opt_positionLocation, 0, options);
  return program;
};

/**
 * Creates a program and buffers for rendering a textured quad with
 * specified lower left and upper right texture coordinates.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Array.<number>} lowerLeftTexCoords The texture coordinates for the lower left corner.
 * @param {!Array.<number>} upperRightTexCoords The texture coordinates for the upper right corner.
 * @param {number} opt_positionLocation The attrib location for position.
 * @param {number} opt_texcoordLocation The attrib location for texture coords.
 * @return {!WebGLProgram}
 */
var setupTexturedQuadWithTexCoords = function(
    gl, lowerLeftTexCoords, upperRightTexCoords,
    opt_positionLocation, opt_texcoordLocation) {
  var program = setupSimpleTextureProgram(
      gl, opt_positionLocation, opt_texcoordLocation);
  setupQuadWithTexCoords(gl, lowerLeftTexCoords, upperRightTexCoords,
                         opt_positionLocation, opt_texcoordLocation);
  return program;
};

/**
 * Creates a program and buffers for rendering a textured quad with
 * a cube map texture.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} opt_positionLocation The attrib location for
 *        position. Default = 0.
 * @param {number} opt_texcoordLocation The attrib location for
 *        texture coords. Default = 1.
 * @return {!WebGLProgram}
 */
var setupTexturedQuadWithCubeMap = function(
    gl, opt_positionLocation, opt_texcoordLocation) {
  var program = setupSimpleCubeMapTextureProgram(
      gl, opt_positionLocation, opt_texcoordLocation);
  setupUnitQuad(gl, opt_positionLocation, opt_texcoordLocation, undefined);
  return program;
};

/**
 * Creates a unit quad with only positions of a given resolution.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} gridRes The resolution of the mesh grid,
 *     expressed in the number of quads across and down.
 * @param {number} opt_positionLocation The attrib location for position.
 */
var setupIndexedQuad = function (
    gl, gridRes, opt_positionLocation, opt_flipOddTriangles) {
  return setupIndexedQuadWithOptions(gl,
    { gridRes: gridRes,
      positionLocation: opt_positionLocation,
      flipOddTriangles: opt_flipOddTriangles
    });
};

/**
 * Creates a quad with various options.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Object} options The options. See below.
 * @return {!Array.<WebGLBuffer>} The created buffers.
 *     [positions, <colors>, indices]
 *
 * Options:
 *   gridRes: number of quads across and down grid.
 *   positionLocation: attrib location for position
 *   flipOddTriangles: reverse order of vertices of every other
 *       triangle
 *   positionOffset: offset added to each vertex
 *   positionMult: multipier for each vertex
 *   colorLocation: attrib location for vertex colors. If
 *      undefined no vertex colors will be created.
 */
var setupIndexedQuadWithOptions = function (gl, options) {
  var positionLocation = options.positionLocation || 0;
  var objects = [];

  var gridRes = options.gridRes || 1;
  var positionOffset = options.positionOffset || 0;
  var positionMult = options.positionMult || 1;
  var vertsAcross = gridRes + 1;
  var numVerts = vertsAcross * vertsAcross;
  var positions = new Float32Array(numVerts * 3);
  var indices = new Uint16Array(6 * gridRes * gridRes);
  var poffset = 0;

  for (var yy = 0; yy <= gridRes; ++yy) {
    for (var xx = 0; xx <= gridRes; ++xx) {
      positions[poffset + 0] = (-1 + 2 * xx / gridRes) * positionMult + positionOffset;
      positions[poffset + 1] = (-1 + 2 * yy / gridRes) * positionMult + positionOffset;
      positions[poffset + 2] = 0;

      poffset += 3;
    }
  }

  var buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STATIC_DRAW);
  gl.enableVertexAttribArray(positionLocation);
  gl.vertexAttribPointer(positionLocation, 3, gl.FLOAT, false, 0, 0);
  objects.push(buf);

  if (options.colorLocation !== undefined) {
    var colors = new Float32Array(numVerts * 4);
    poffset = 0;
    for (var yy = 0; yy <= gridRes; ++yy) {
      for (var xx = 0; xx <= gridRes; ++xx) {
        if (options.color !== undefined) {
          colors[poffset + 0] = options.color[0];
          colors[poffset + 1] = options.color[1];
          colors[poffset + 2] = options.color[2];
          colors[poffset + 3] = options.color[3];
        } else {
          colors[poffset + 0] = xx / gridRes;
          colors[poffset + 1] = yy / gridRes;
          colors[poffset + 2] = (xx / gridRes) * (yy / gridRes);
          colors[poffset + 3] = (yy % 2) * 0.5 + 0.5;
        }
        poffset += 4;
      }
    }

    buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, colors, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(options.colorLocation);
    gl.vertexAttribPointer(options.colorLocation, 4, gl.FLOAT, false, 0, 0);
    objects.push(buf);
  }

  var tbase = 0;
  for (var yy = 0; yy < gridRes; ++yy) {
    var index = yy * vertsAcross;
    for (var xx = 0; xx < gridRes; ++xx) {
      indices[tbase + 0] = index + 0;
      indices[tbase + 1] = index + 1;
      indices[tbase + 2] = index + vertsAcross;
      indices[tbase + 3] = index + vertsAcross;
      indices[tbase + 4] = index + 1;
      indices[tbase + 5] = index + vertsAcross + 1;

      if (options.flipOddTriangles) {
        indices[tbase + 4] = index + vertsAcross + 1;
        indices[tbase + 5] = index + 1;
      }

      index += 1;
      tbase += 6;
    }
  }

  buf = gl.createBuffer();
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buf);
  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
  objects.push(buf);

  return objects;
};

/**
 * Returns the constructor for a typed array that corresponds to the given
 * WebGL type.
 * @param {!WebGLRenderingContext} gl A WebGLRenderingContext.
 * @param {number} type The WebGL type (eg, gl.UNSIGNED_BYTE)
 * @return {!Constructor} The typed array constructor that
 *      corresponds to the given type.
 */
var glTypeToTypedArrayType = function(gl, type) {
  switch (type) {
    case gl.BYTE:
      return window.Int8Array;
    case gl.UNSIGNED_BYTE:
      return window.Uint8Array;
    case gl.SHORT:
      return window.Int16Array;
    case gl.UNSIGNED_SHORT:
    case gl.UNSIGNED_SHORT_5_6_5:
    case gl.UNSIGNED_SHORT_4_4_4_4:
    case gl.UNSIGNED_SHORT_5_5_5_1:
      return window.Uint16Array;
    case gl.INT:
      return window.Int32Array;
    case gl.UNSIGNED_INT:
    case gl.UNSIGNED_INT_5_9_9_9_REV:
    case gl.UNSIGNED_INT_10F_11F_11F_REV:
    case gl.UNSIGNED_INT_2_10_10_10_REV:
    case gl.UNSIGNED_INT_24_8:
      return window.Uint32Array;
    case gl.HALF_FLOAT:
    case 0x8D61:  // HALF_FLOAT_OES
      return window.Uint16Array;
    case gl.FLOAT:
      return window.Float32Array;
    default:
      throw 'unknown gl type ' + glEnumToString(gl, type);
  }
};

/**
 * Returns the number of bytes per component for a given WebGL type.
 * @param {!WebGLRenderingContext} gl A WebGLRenderingContext.
 * @param {GLenum} type The WebGL type (eg, gl.UNSIGNED_BYTE)
 * @return {number} The number of bytes per component.
 */
var getBytesPerComponent = function(gl, type) {
  switch (type) {
    case gl.BYTE:
    case gl.UNSIGNED_BYTE:
      return 1;
    case gl.SHORT:
    case gl.UNSIGNED_SHORT:
    case gl.UNSIGNED_SHORT_5_6_5:
    case gl.UNSIGNED_SHORT_4_4_4_4:
    case gl.UNSIGNED_SHORT_5_5_5_1:
    case gl.HALF_FLOAT:
    case 0x8D61:  // HALF_FLOAT_OES
      return 2;
    case gl.INT:
    case gl.UNSIGNED_INT:
    case gl.UNSIGNED_INT_5_9_9_9_REV:
    case gl.UNSIGNED_INT_10F_11F_11F_REV:
    case gl.UNSIGNED_INT_2_10_10_10_REV:
    case gl.UNSIGNED_INT_24_8:
    case gl.FLOAT:
      return 4;
    default:
      throw 'unknown gl type ' + glEnumToString(gl, type);
  }
};

/**
 * Returns the number of typed array elements per pixel for a given WebGL
 * format/type combination. The corresponding typed array type can be determined
 * by calling glTypeToTypedArrayType.
 * @param {!WebGLRenderingContext} gl A WebGLRenderingContext.
 * @param {GLenum} format The WebGL format (eg, gl.RGBA)
 * @param {GLenum} type The WebGL type (eg, gl.UNSIGNED_BYTE)
 * @return {number} The number of typed array elements per pixel.
 */
var getTypedArrayElementsPerPixel = function(gl, format, type) {
  switch (type) {
    case gl.UNSIGNED_SHORT_5_6_5:
    case gl.UNSIGNED_SHORT_4_4_4_4:
    case gl.UNSIGNED_SHORT_5_5_5_1:
      return 1;
    case gl.UNSIGNED_BYTE:
      break;
    default:
      throw 'not a gl type for color information ' + glEnumToString(gl, type);
  }

  switch (format) {
    case gl.RGBA:
      return 4;
    case gl.RGB:
      return 3;
    case gl.LUMINANCE_ALPHA:
      return 2;
    case gl.LUMINANCE:
    case gl.ALPHA:
      return 1;
    default:
      throw 'unknown gl format ' + glEnumToString(gl, format);
  }
};

/**
 * Fills the given texture with a solid color.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!WebGLTexture} tex The texture to fill.
 * @param {number} width The width of the texture to create.
 * @param {number} height The height of the texture to create.
 * @param {!Array.<number>} color The color to fill with.
 *        where each element is in the range 0 to 255.
 * @param {number} opt_level The level of the texture to fill. Default = 0.
 * @param {number} opt_format The format for the texture.
 * @param {number} opt_internalFormat The internal format for the texture.
 */
var fillTexture = function(gl, tex, width, height, color, opt_level, opt_format, opt_type, opt_internalFormat) {
  opt_level = opt_level || 0;
  opt_format = opt_format || gl.RGBA;
  opt_type = opt_type || gl.UNSIGNED_BYTE;
  opt_internalFormat = opt_internalFormat || opt_format;
  var pack = gl.getParameter(gl.UNPACK_ALIGNMENT);
  var numComponents = color.length;
  var bytesPerComponent = getBytesPerComponent(gl, opt_type);
  var rowSize = numComponents * width * bytesPerComponent;
  // See equation 3.10 in ES 2.0 spec and equation 3.13 in ES 3.0 spec for paddedRowLength calculation.
  // k is paddedRowLength.
  // n is numComponents.
  // l is width.
  // a is pack.
  // s is bytesPerComponent.
  var paddedRowLength;
  if (bytesPerComponent >= pack)
    paddedRowLength = numComponents * width;
  else
    paddedRowLength = Math.floor((rowSize + pack - 1) / pack) * pack / bytesPerComponent;
  var size = width * numComponents + (height - 1) * paddedRowLength;
  var buf = new (glTypeToTypedArrayType(gl, opt_type))(size);
  for (var yy = 0; yy < height; ++yy) {
    var off = yy * paddedRowLength;
    for (var xx = 0; xx < width; ++xx) {
      for (var jj = 0; jj < numComponents; ++jj) {
        buf[off++] = color[jj];
      }
    }
  }
  gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.texImage2D(
      gl.TEXTURE_2D, opt_level, opt_internalFormat, width, height, 0,
      opt_format, opt_type, buf);
};

/**
 * Creates a texture and fills it with a solid color.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} width The width of the texture to create.
 * @param {number} height The height of the texture to create.
 * @param {!Array.<number>} color The color to fill with. A 4 element array
 *        where each element is in the range 0 to 255.
 * @return {!WebGLTexture}
 */
var createColoredTexture = function(gl, width, height, color) {
  var tex = gl.createTexture();
  fillTexture(gl, tex, width, height, color);
  return tex;
};

var ubyteToFloat = function(c) {
  return c / 255;
};

var ubyteColorToFloatColor = function(color) {
  var floatColor = [];
  for (var ii = 0; ii < color.length; ++ii) {
    floatColor[ii] = ubyteToFloat(color[ii]);
  }
  return floatColor;
};

/**
 * Sets the "u_color" uniform of the current program to color.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Array.<number>} color 4 element array of 0-1 color
 *      components.
 */
var setFloatDrawColor = function(gl, color) {
  var program = gl.getParameter(gl.CURRENT_PROGRAM);
  var colorLocation = gl.getUniformLocation(program, "u_color");
  gl.uniform4fv(colorLocation, color);
};

/**
 * Sets the "u_color" uniform of the current program to color.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Array.<number>} color 4 element array of 0-255 color
 *      components.
 */
var setUByteDrawColor = function(gl, color) {
  setFloatDrawColor(gl, ubyteColorToFloatColor(color));
};

/**
 * Draws a previously setup quad in the given color.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Array.<number>} color The color to draw with. A 4
 *        element array where each element is in the range 0 to
 *        1.
 */
var drawFloatColorQuad = function(gl, color) {
  var program = gl.getParameter(gl.CURRENT_PROGRAM);
  var colorLocation = gl.getUniformLocation(program, "u_color");
  gl.uniform4fv(colorLocation, color);
  gl.drawArrays(gl.TRIANGLES, 0, 6);
};


/**
 * Draws a previously setup quad in the given color.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Array.<number>} color The color to draw with. A 4
 *        element array where each element is in the range 0 to
 *        255.
 */
var drawUByteColorQuad = function(gl, color) {
  drawFloatColorQuad(gl, ubyteColorToFloatColor(color));
};

/**
 * Draws a previously setupUnitQuad.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 */
var drawUnitQuad = function(gl) {
  gl.drawArrays(gl.TRIANGLES, 0, 6);
};

var dummySetProgramAndDrawNothing = function(gl) {
  if (!gl._wtuDummyProgram) {
    gl._wtuDummyProgram = setupProgram(gl, [
      "void main() { gl_Position = vec4(0.0); }",
      "void main() { gl_FragColor = vec4(0.0); }"
    ], [], []);
  }
  gl.useProgram(gl._wtuDummyProgram);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
};

/**
 * Clears then Draws a previously setupUnitQuad.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!Array.<number>} opt_color The color to fill clear with before
 *        drawing. A 4 element array where each element is in the range 0 to
 *        255. Default [255, 255, 255, 255]
 */
var clearAndDrawUnitQuad = function(gl, opt_color) {
  opt_color = opt_color || [255, 255, 255, 255];
  gl.clearColor(
      opt_color[0] / 255,
      opt_color[1] / 255,
      opt_color[2] / 255,
      opt_color[3] / 255);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
  drawUnitQuad(gl);
};

/**
 * Draws a quad previously setup with setupIndexedQuad.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} gridRes Resolution of grid.
 */
var drawIndexedQuad = function(gl, gridRes) {
  gl.drawElements(gl.TRIANGLES, gridRes * gridRes * 6, gl.UNSIGNED_SHORT, 0);
};

/**
 * Draws a previously setupIndexedQuad
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number} gridRes Resolution of grid.
 * @param {!Array.<number>} opt_color The color to fill clear with before
 *        drawing. A 4 element array where each element is in the range 0 to
 *        255. Default [255, 255, 255, 255]
 */
var clearAndDrawIndexedQuad = function(gl, gridRes, opt_color) {
  opt_color = opt_color || [255, 255, 255, 255];
  gl.clearColor(
      opt_color[0] / 255,
      opt_color[1] / 255,
      opt_color[2] / 255,
      opt_color[3] / 255);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
  drawIndexedQuad(gl, gridRes);
};

/**
 * Clips a range to min, max
 * (Eg. clipToRange(-5,7,0,20) would return {value:0,extent:2}
 * @param {number} value start of range
 * @param {number} extent extent of range
 * @param {number} min min.
 * @param {number} max max.
 * @return {!{value:number,extent:number}} The clipped value.
 */
var clipToRange = function(value, extent, min, max) {
  if (value < min) {
    extent -= min - value;
    value = min;
  }
  var end = value + extent;
  if (end > max) {
    extent -= end - max;
  }
  if (extent < 0) {
    value = max;
    extent = 0;
  }
  return {value:value, extent: extent};
};

/**
 * Determines if the passed context is an instance of a WebGLRenderingContext
 * or later variant (like WebGL2RenderingContext)
 * @param {CanvasRenderingContext} ctx The context to check.
 */
var isWebGLContext = function(ctx) {
  if (ctx instanceof WebGLRenderingContext)
    return true;

  if ('WebGL2RenderingContext' in window && ctx instanceof WebGL2RenderingContext)
    return true;

  return false;
};

/**
 * Creates a check rect is used by checkCanvasRects.
 * @param {number} x left corner of region to check.
 * @param {number} y bottom corner of region to check in case of checking from
 *        a GL context or top corner in case of checking from a 2D context.
 * @param {number} width width of region to check.
 * @param {number} height width of region to check.
 * @param {!Array.<number>} color The color expected. A 4 element array where
 *        each element is in the range 0 to 255.
 * @param {string} opt_msg Message to associate with success. Eg
 *        ("should be red").
 * @param {number} opt_errorRange Optional. Acceptable error in
 *        color checking. 0 by default.
 */
var makeCheckRect = function(x, y, width, height, color, msg, errorRange) {
  var rect = {
    'x': x, 'y': y,
    'width': width, 'height': height,
    'color': color, 'msg': msg,
    'errorRange': errorRange,

    'checkRect': function (buf, l, b, w) {
      for (var px = (x - l) ; px < (x + width - l) ; ++px) {
        for (var py = (y - b) ; py < (y + height - b) ; ++py) {
          var offset = (py * w + px) * 4;
          for (var j = 0; j < color.length; ++j) {
            if (Math.abs(buf[offset + j] - color[j]) > errorRange) {
              testFailed(msg);
              var was = buf[offset + 0].toString();
              for (j = 1; j < color.length; ++j) {
                was += "," + buf[offset + j];
              }
              debug('at (' + px + ', ' + py +
                    ') expected: ' + color + ' was ' + was);
              return;
            }
          }
        }
      }
      testPassed(msg);
    }
  }
  return rect;
};

/**
 * Checks that a portions of a canvas or the currently attached framebuffer is 1 color.
 * @param {!WebGLRenderingContext|CanvasRenderingContext2D} gl The
 *         WebGLRenderingContext or 2D context to use.
 * @param {!Array.<checkRect>} array of rects to check for matching color.
 */
var checkCanvasRects = function(gl, rects) {
  if (rects.length > 0) {
    var left = rects[0].x;
    var right = rects[0].x + rects[1].width;
    var bottom = rects[0].y;
    var top = rects[0].y + rects[0].height;
    for (var i = 1; i < rects.length; ++i) {
      left = Math.min(left, rects[i].x);
      right = Math.max(right, rects[i].x + rects[i].width);
      bottom = Math.min(bottom, rects[i].y);
      top = Math.max(top, rects[i].y + rects[i].height);
    }
    var width = right - left;
    var height = top - bottom;
    var buf = new Uint8Array(width * height * 4);
    gl.readPixels(left, bottom, width, height, gl.RGBA, gl.UNSIGNED_BYTE, buf);
    for (var i = 0; i < rects.length; ++i) {
      rects[i].checkRect(buf, left, bottom, width);
    }
  }
};

/**
 * Checks that a portion of a canvas or the currently attached framebuffer is 1 color.
 * @param {!WebGLRenderingContext|CanvasRenderingContext2D} gl The
 *         WebGLRenderingContext or 2D context to use.
 * @param {number} x left corner of region to check.
 * @param {number} y bottom corner of region to check in case of checking from
 *        a GL context or top corner in case of checking from a 2D context.
 * @param {number} width width of region to check.
 * @param {number} height width of region to check.
 * @param {!Array.<number>} color The color expected. A 4 element array where
 *        each element is in the range 0 to 255.
 * @param {number} opt_errorRange Optional. Acceptable error in
 *        color checking. 0 by default.
 * @param {!function()} sameFn Function to call if all pixels
 *        are the same as color.
 * @param {!function()} differentFn Function to call if a pixel
 *        is different than color
 * @param {!function()} logFn Function to call for logging.
 * @param {TypedArray} opt_readBackBuf optional buffer to read back into.
 *        Typically passed to either reuse buffer, or support readbacks from
 *        floating-point/norm16 framebuffers.
 * @param {GLenum} opt_readBackType optional read back type, defaulting to
 *        gl.UNSIGNED_BYTE. Can be used to support readback from floating-point
 *        /norm16 framebuffers.
 * @param {GLenum} opt_readBackFormat optional read back format, defaulting to
 *        gl.RGBA. Can be used to support readback from norm16
 *        framebuffers.
 */
var checkCanvasRectColor = function(gl, x, y, width, height, color, opt_errorRange, sameFn, differentFn, logFn, opt_readBackBuf, opt_readBackType, opt_readBackFormat) {
  if (isWebGLContext(gl) && !gl.getParameter(gl.FRAMEBUFFER_BINDING)) {
    // We're reading the backbuffer so clip.
    var xr = clipToRange(x, width, 0, gl.canvas.width);
    var yr = clipToRange(y, height, 0, gl.canvas.height);
    if (!xr.extent || !yr.extent) {
      logFn("checking rect: effective width or height is zero");
      sameFn();
      return;
    }
    x = xr.value;
    y = yr.value;
    width = xr.extent;
    height = yr.extent;
  }
  var errorRange = opt_errorRange || 0;
  if (!errorRange.length) {
    errorRange = [errorRange, errorRange, errorRange, errorRange]
  }
  var buf;
  if (isWebGLContext(gl)) {
    buf = opt_readBackBuf ? opt_readBackBuf : new Uint8Array(width * height * 4);
    var readBackType = opt_readBackType ? opt_readBackType : gl.UNSIGNED_BYTE;
    var readBackFormat = opt_readBackFormat ? opt_readBackFormat : gl.RGBA;
    gl.readPixels(x, y, width, height, readBackFormat, readBackType, buf);
  } else {
    buf = gl.getImageData(x, y, width, height).data;
  }
  for (var i = 0; i < width * height; ++i) {
    var offset = i * 4;
    for (var j = 0; j < color.length; ++j) {
      if (Math.abs(buf[offset + j] - color[j]) > errorRange[j]) {
        var was = buf[offset + 0].toString();
        for (j = 1; j < color.length; ++j) {
          was += "," + buf[offset + j];
        }
        differentFn('at (' + (x + (i % width)) + ', ' + (y + Math.floor(i / width)) +
                    ') expected: ' + color + ' was ' + was, buf);
        return;
      }
    }
  }
  sameFn();
};

/**
 * Checks that a portion of a canvas or the currently attached framebuffer is 1 color.
 * @param {!WebGLRenderingContext|CanvasRenderingContext2D} gl The
 *         WebGLRenderingContext or 2D context to use.
 * @param {number} x left corner of region to check.
 * @param {number} y bottom corner of region to check in case of checking from
 *        a GL context or top corner in case of checking from a 2D context.
 * @param {number} width width of region to check.
 * @param {number} height width of region to check.
 * @param {!Array.<number>} color The color expected. A 4 element array where
 *        each element is in the range 0 to 255.
 * @param {string} opt_msg Message to associate with success or failure. Eg
 *        ("should be red").
 * @param {number} opt_errorRange Optional. Acceptable error in
 *        color checking. 0 by default.
 * @param {TypedArray} opt_readBackBuf optional buffer to read back into.
 *        Typically passed to either reuse buffer, or support readbacks from
 *        floating-point/norm16 framebuffers.
 * @param {GLenum} opt_readBackType optional read back type, defaulting to
 *        gl.UNSIGNED_BYTE. Can be used to support readback from floating-point
 *        /norm16 framebuffers.
 * @param {GLenum} opt_readBackFormat optional read back format, defaulting to
 *        gl.RGBA. Can be used to support readback from floating-point
 *        /norm16 framebuffers.
 */
var checkCanvasRect = function(gl, x, y, width, height, color, opt_msg, opt_errorRange, opt_readBackBuf, opt_readBackType, opt_readBackFormat) {
  checkCanvasRectColor(
      gl, x, y, width, height, color, opt_errorRange,
      function() {
        var msg = opt_msg;
        if (msg === undefined)
          msg = "should be " + color.toString();
        testPassed(msg);
      },
      function(differentMsg) {
        var msg = opt_msg;
        if (msg === undefined)
          msg = "should be " + color.toString();
        testFailed(msg + "\n" + differentMsg);
      },
      debug,
      opt_readBackBuf,
      opt_readBackType,
      opt_readBackFormat);
};

/**
 * Checks that an entire canvas or the currently attached framebuffer is 1 color.
 * @param {!WebGLRenderingContext|CanvasRenderingContext2D} gl The
 *         WebGLRenderingContext or 2D context to use.
 * @param {!Array.<number>} color The color expected. A 4 element array where
 *        each element is in the range 0 to 255.
 * @param {string} msg Message to associate with success. Eg ("should be red").
 * @param {number} errorRange Optional. Acceptable error in
 *        color checking. 0 by default.
 */
var checkCanvas = function(gl, color, msg, errorRange) {
  checkCanvasRect(gl, 0, 0, gl.canvas.width, gl.canvas.height, color, msg, errorRange);
};

/**
 * Checks a rectangular area both inside the area and outside
 * the area.
 * @param {!WebGLRenderingContext|CanvasRenderingContext2D} gl The
 *         WebGLRenderingContext or 2D context to use.
 * @param {number} x left corner of region to check.
 * @param {number} y bottom corner of region to check in case of checking from
 *        a GL context or top corner in case of checking from a 2D context.
 * @param {number} width width of region to check.
 * @param {number} height width of region to check.
 * @param {!Array.<number>} innerColor The color expected inside
 *     the area. A 4 element array where each element is in the
 *     range 0 to 255.
 * @param {!Array.<number>} outerColor The color expected
 *     outside. A 4 element array where each element is in the
 *     range 0 to 255.
 * @param {!number} opt_edgeSize: The number of pixels to skip
 *     around the edges of the area. Defaut 0.
 * @param {!{width:number, height:number}} opt_outerDimensions
 *     The outer dimensions. Default the size of gl.canvas.
 */
var checkAreaInAndOut = function(gl, x, y, width, height, innerColor, outerColor, opt_edgeSize, opt_outerDimensions) {
  var outerDimensions = opt_outerDimensions || { width: gl.canvas.width, height: gl.canvas.height };
  var edgeSize = opt_edgeSize || 0;
  checkCanvasRect(gl, x + edgeSize, y + edgeSize, width - edgeSize * 2, height - edgeSize * 2, innerColor);
  checkCanvasRect(gl, 0, 0, x - edgeSize, outerDimensions.height, outerColor);
  checkCanvasRect(gl, x + width + edgeSize, 0, outerDimensions.width - x - width - edgeSize, outerDimensions.height, outerColor);
  checkCanvasRect(gl, 0, 0, outerDimensions.width, y - edgeSize, outerColor);
  checkCanvasRect(gl, 0, y + height + edgeSize, outerDimensions.width, outerDimensions.height - y - height - edgeSize, outerColor);
};

/**
 * Checks that an entire buffer matches the floating point values provided.
 * (WebGL 2.0 only)
 * @param {!WebGL2RenderingContext} gl The WebGL2RenderingContext to use.
 * @param {number} target The buffer target to bind to.
 * @param {!Array.<number>} expected The values expected.
 * @param {string} opt_msg Optional. Message to associate with success. Eg ("should be red").
 * @param {number} opt_errorRange Optional. Acceptable error in value checking. 0.001 by default.
 */
var checkFloatBuffer = function(gl, target, expected, opt_msg, opt_errorRange) {
  if (opt_msg === undefined)
    opt_msg = "buffer should match expected values";

  if (opt_errorRange === undefined)
    opt_errorRange = 0.001;

  var floatArray = new Float32Array(expected.length);
  gl.getBufferSubData(target, 0, floatArray);

  for (var i = 0; i < expected.length; i++) {
    if (Math.abs(floatArray[i] - expected[i]) > opt_errorRange) {
      testFailed(opt_msg);
      debug('at [' + i + '] expected: ' + expected[i] + ' was ' + floatArray[i]);
      return;
    }
  }
  testPassed(opt_msg);
};

/**
 * Loads a texture, calls callback when finished.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} url URL of image to load
 * @param {function(!Image): void} callback Function that gets called after
 *        image has loaded
 * @return {!WebGLTexture} The created texture.
 */
var loadTexture = function(gl, url, callback) {
    var texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    var image = new Image();
    image.onload = function() {
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
        callback(image);
    };
    image.src = url;
    return texture;
};

/**
 * Checks whether the bound texture has expected dimensions. One corner pixel
 * of the texture will be changed as a side effect.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!WebGLTexture} texture The texture to check.
 * @param {number} width Expected width.
 * @param {number} height Expected height.
 * @param {GLenum} opt_format The texture's format. Defaults to RGBA.
 * @param {GLenum} opt_type The texture's type. Defaults to UNSIGNED_BYTE.
 */
var checkTextureSize = function(gl, width, height, opt_format, opt_type) {
  opt_format = opt_format || gl.RGBA;
  opt_type = opt_type || gl.UNSIGNED_BYTE;

  var numElements = getTypedArrayElementsPerPixel(gl, opt_format, opt_type);
  var buf = new (glTypeToTypedArrayType(gl, opt_type))(numElements);

  var errors = 0;
  gl.texSubImage2D(gl.TEXTURE_2D, 0, width - 1, height - 1, 1, 1, opt_format, opt_type, buf);
  if (gl.getError() != gl.NO_ERROR) {
    testFailed("Texture was smaller than the expected size " + width + "x" + height);
    ++errors;
  }
  gl.texSubImage2D(gl.TEXTURE_2D, 0, width - 1, height, 1, 1, opt_format, opt_type, buf);
  if (gl.getError() == gl.NO_ERROR) {
    testFailed("Texture was taller than " + height);
    ++errors;
  }
  gl.texSubImage2D(gl.TEXTURE_2D, 0, width, height - 1, 1, 1, opt_format, opt_type, buf);
  if (gl.getError() == gl.NO_ERROR) {
    testFailed("Texture was wider than " + width);
    ++errors;
  }
  if (errors == 0) {
    testPassed("Texture had the expected size " + width + "x" + height);
  }
};

/**
 * Makes a shallow copy of an object.
 * @param {!Object} src Object to copy
 * @return {!Object} The copy of src.
 */
var shallowCopyObject = function(src) {
  var dst = {};
  for (var attr in src) {
    if (src.hasOwnProperty(attr)) {
      dst[attr] = src[attr];
    }
  }
  return dst;
};

/**
 * Checks if an attribute exists on an object case insensitive.
 * @param {!Object} obj Object to check
 * @param {string} attr Name of attribute to look for.
 * @return {string?} The name of the attribute if it exists,
 *         undefined if not.
 */
var hasAttributeCaseInsensitive = function(obj, attr) {
  var lower = attr.toLowerCase();
  for (var key in obj) {
    if (obj.hasOwnProperty(key) && key.toLowerCase() == lower) {
      return key;
    }
  }
};

/**
 * Returns a map of URL querystring options
 * @return {Object?} Object containing all the values in the URL querystring
 */
var getUrlOptions = (function() {
  var _urlOptionsParsed = false;
  var _urlOptions = {};
  return function() {
    if (!_urlOptionsParsed) {
      var s = window.location.href;
      var q = s.indexOf("?");
      var e = s.indexOf("#");
      if (e < 0) {
        e = s.length;
      }
      var query = s.substring(q + 1, e);
      var pairs = query.split("&");
      for (var ii = 0; ii < pairs.length; ++ii) {
        var keyValue = pairs[ii].split("=");
        var key = keyValue[0];
        var value = decodeURIComponent(keyValue[1]);
        _urlOptions[key] = value;
      }
      _urlOptionsParsed = true;
    }

    return _urlOptions;
  }
})();

var default3DContextVersion = 1;

/**
 * Set the default context version for create3DContext.
 * Initially the default version is 1.
 * @param {number} Default version of WebGL contexts.
 */
var setDefault3DContextVersion = function(version) {
    default3DContextVersion = version;
};

/**
 * Get the default contex version for create3DContext.
 * First it looks at the URI option |webglVersion|. If it does not exist,
 * then look at the global default3DContextVersion variable.
 */
var getDefault3DContextVersion = function() {
    return parseInt(getUrlOptions().webglVersion, 10) || default3DContextVersion;
};

/**
 * Creates a webgl context.
 * @param {!Canvas|string} opt_canvas The canvas tag to get
 *     context from. If one is not passed in one will be
 *     created. If it's a string it's assumed to be the id of a
 *     canvas.
 * @param {Object} opt_attributes Context attributes.
 * @param {!number} opt_version Version of WebGL context to create.
 *     The default version can be set by calling setDefault3DContextVersion.
 * @return {!WebGLRenderingContext} The created context.
 */
var create3DContext = function(opt_canvas, opt_attributes, opt_version) {
  if (window.initTestingHarness) {
    window.initTestingHarness();
  }
  var attributes = shallowCopyObject(opt_attributes || {});
  if (!hasAttributeCaseInsensitive(attributes, "antialias")) {
    attributes.antialias = false;
  }

  const parseString = v => v;
  const parseBoolean = v => v.toLowerCase().startsWith('t') || parseFloat(v) > 0;
  const params = new URLSearchParams(window.location.search);
  for (const [key, parseFn] of Object.entries({
    alpha: parseBoolean,
    antialias: parseBoolean,
    depth: parseBoolean,
    desynchronized: parseBoolean,
    failIfMajorPerformanceCaveat: parseBoolean,
    powerPreference: parseString,
    premultipliedAlpha: parseBoolean,
    preserveDrawingBuffer: parseBoolean,
    stencil: parseBoolean,
  })) {
    const value = params.get(key);
    if (value) {
      const v = parseFn(value);
      attributes[key] = v;
      debug(`setting context attribute: ${key} = ${v}`);
    }
  }

  if (!opt_version) {
    opt_version = getDefault3DContextVersion();
  }
  opt_canvas = opt_canvas || document.createElement("canvas");
  if (typeof opt_canvas == 'string') {
    opt_canvas = document.getElementById(opt_canvas);
  }
  var context = null;

  var names;
  switch (opt_version) {
    case 2:
      names = ["webgl2"]; break;
    default:
      names = ["webgl", "experimental-webgl"]; break;
  }

  for (var i = 0; i < names.length; ++i) {
    try {
      context = opt_canvas.getContext(names[i], attributes);
    } catch (e) {
    }
    if (context) {
      break;
    }
  }
  if (!context) {
    testFailed("Unable to fetch WebGL rendering context for Canvas");
  } else {
    if (!window._wtu_contexts) {
      window._wtu_contexts = []
    }
    window._wtu_contexts.push(context);
  }

  if (params.get('showRenderer')) {
    const ext = context.getExtension('WEBGL_debug_renderer_info');
    debug(`RENDERER: ${context.getParameter(ext ? ext.UNMASKED_RENDERER_WEBGL : context.RENDERER)}`);
  }

  return context;
};

/**
 * Indicates whether the given context is WebGL 2.0 or greater.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @return {boolean} True if the given context is WebGL 2.0 or greater.
 */
var isWebGL2 = function(gl) {
  // Duck typing is used so that the conformance suite can be run
  // against libraries emulating WebGL 1.0 on top of WebGL 2.0.
  return !!gl.drawArraysInstanced;
};

/**
 * Defines the exception type for a GL error.
 * @constructor
 * @param {string} message The error message.
 * @param {number} error GL error code
 */
function GLErrorException (message, error) {
   this.message = message;
   this.name = "GLErrorException";
   this.error = error;
};

/**
 * Wraps a WebGL function with a function that throws an exception if there is
 * an error.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} fname Name of function to wrap.
 * @return {function()} The wrapped function.
 */
var createGLErrorWrapper = function(context, fname) {
  return function() {
    var rv = context[fname].apply(context, arguments);
    var err = context.getError();
    if (err != context.NO_ERROR) {
      var msg = "GL error " + glEnumToString(context, err) + " in " + fname;
      throw new GLErrorException(msg, err);
    }
    return rv;
  };
};

/**
 * Creates a WebGL context where all functions are wrapped to throw an exception
 * if there is an error.
 * @param {!Canvas} canvas The HTML canvas to get a context from.
 * @param {Object} opt_attributes Context attributes.
 * @param {!number} opt_version Version of WebGL context to create
 * @return {!Object} The wrapped context.
 */
function create3DContextWithWrapperThatThrowsOnGLError(canvas, opt_attributes, opt_version) {
  var context = create3DContext(canvas, opt_attributes, opt_version);
  var wrap = {};
  for (var i in context) {
    try {
      if (typeof context[i] == 'function') {
        wrap[i] = createGLErrorWrapper(context, i);
      } else {
        wrap[i] = context[i];
      }
    } catch (e) {
      error("createContextWrapperThatThrowsOnGLError: Error accessing " + i);
    }
  }
  wrap.getError = function() {
      return context.getError();
  };
  return wrap;
};

/**
 * Tests that an evaluated expression generates a specific GL error.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number|Array.<number>} glErrors The expected gl error or an array of expected errors.
 * @param {string} evalStr The string to evaluate.
 */
var shouldGenerateGLError = function(gl, glErrors, evalStr, opt_msg) {
  var exception;
  try {
    eval(evalStr);
  } catch (e) {
    exception = e;
  }
  if (exception) {
    testFailed(evalStr + " threw exception " + exception);
    return -1;
  } else {
    if (!opt_msg) {
      opt_msg = "after evaluating: " + evalStr;
    }
    return glErrorShouldBe(gl, glErrors, opt_msg);
  }
};

/**
 * Tests that an evaluated expression does not generate a GL error.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} evalStr The string to evaluate.
 */
var failIfGLError = function(gl, evalStr) {
  var exception;
  try {
    eval(evalStr);
  } catch (e) {
    exception = e;
  }
  if (exception) {
    testFailed(evalStr + " threw exception " + exception);
  } else {
    glErrorShouldBeImpl(gl, gl.NO_ERROR, false, "after evaluating: " + evalStr);
  }
};

/**
 * Tests that the first error GL returns is the specified error.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number|Array.<number>} glErrors The expected gl error or an array of expected errors.
 * @param {string} opt_msg Optional additional message.
 */
var glErrorShouldBe = function(gl, glErrors, opt_msg) {
  return glErrorShouldBeImpl(gl, glErrors, true, opt_msg);
};

const glErrorAssert = function(gl, glErrors, opt_msg) {
  return glErrorShouldBeImpl(gl, glErrors, false, opt_msg);
};

/**
 * Tests that the given framebuffer has a specific status
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number|Array.<number>} glStatuses The expected gl
 *        status or an array of expected statuses.
 * @param {string} opt_msg Optional additional message.
 */
var framebufferStatusShouldBe = function(gl, target, glStatuses, opt_msg) {
  if (!glStatuses.length) {
    glStatuses = [glStatuses];
  }
  opt_msg = opt_msg || "";
  const status = gl.checkFramebufferStatus(target);
  const ndx = glStatuses.indexOf(status);
  const expected = glStatuses.map((status) => {
    return glEnumToString(gl, status);
  }).join(' or ');
  if (ndx < 0) {
    let msg = "checkFramebufferStatus expected" + ((glStatuses.length > 1) ? " one of: " : ": ") +
      expected +  ". Was " + glEnumToString(gl, status);
    if (opt_msg) {
      msg += ": " + opt_msg;
    }
    testFailed(msg);
    return false;
  }
  let msg = `checkFramebufferStatus was ${glEnumToString(gl, status)}`;
  if (glStatuses.length > 1) {
    msg += `, one of: ${expected}`;
  }
  if (opt_msg) {
    msg += ": " + opt_msg;
  }
  testPassed(msg);
  return [status];
}

/**
 * Tests that the first error GL returns is the specified error. Allows suppression of successes.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {number|Array.<number>} glErrors The expected gl error or an array of expected errors.
 * @param {boolean} reportSuccesses Whether to report successes as passes, or to silently pass.
 * @param {string} opt_msg Optional additional message.
 */
var glErrorShouldBeImpl = function(gl, glErrors, reportSuccesses, opt_msg) {
  if (!glErrors.length) {
    glErrors = [glErrors];
  }
  opt_msg = opt_msg || "";

  const fnErrStr = function(errVal) {
    if (errVal == 0) return "NO_ERROR";
    return glEnumToString(gl, errVal);
  };

  var err = gl.getError();
  var ndx = glErrors.indexOf(err);
  var errStrs = [];
  for (var ii = 0; ii < glErrors.length; ++ii) {
    errStrs.push(fnErrStr(glErrors[ii]));
  }
  var expected = errStrs.join(" or ");
  if (ndx < 0) {
    var msg = "getError expected" + ((glErrors.length > 1) ? " one of: " : ": ");
    testFailed(msg + expected +  ". Was " + fnErrStr(err) + " : " + opt_msg);
  } else if (reportSuccesses) {
    var msg = "getError was " + ((glErrors.length > 1) ? "one of: " : "expected value: ");
    testPassed(msg + expected + " : " + opt_msg);
  }
  return err;
};

/**
 * Tests that a function throws or not.
 * @param {!WebGLContext} gl The WebGLContext to use.
 * @param throwType Type of thrown error (e.g. TypeError), or false.
 * @param {string} info Info on what's being tested
 * @param {function} func The func to test.
 */
var shouldThrow = function(gl, throwType, info, func) {
  while (gl.getError()) {}

  var shouldThrow = (throwType != false);

  try {
    func();

    if (shouldThrow) {
      testFailed("Should throw a " + throwType.name + ": " + info);
    } else {
      testPassed("Should not have thrown: " + info);
    }
  } catch (e) {
    if (shouldThrow) {
      if (e instanceof throwType) {
        testPassed("Should throw a " + throwType.name + ": " + info);
      } else {
        testFailed("Should throw a " + throwType.name + ", threw " + e.name + ": " + info);
      }
    } else {
      testFailed("Should not have thrown: " + info);
    }

    if (gl.getError()) {
      testFailed("Should not generate an error when throwing: " + info);
    }
  }

  while (gl.getError()) {}
};

/**
 * Links a WebGL program, throws if there are errors.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!WebGLProgram} program The WebGLProgram to link.
 * @param {function(string): void} opt_errorCallback callback for errors.
 */
var linkProgram = function(gl, program, opt_errorCallback) {
  var errFn = opt_errorCallback || testFailed;
  // Link the program
  gl.linkProgram(program);

  // Check the link status
  var linked = gl.getProgramParameter(program, gl.LINK_STATUS);
  if (!linked) {
    // something went wrong with the link
    var error = gl.getProgramInfoLog (program);

    errFn("Error in program linking:" + error);

    gl.deleteProgram(program);
  }
};

/**
 * Loads text from an external file. This function is asynchronous.
 * @param {string} url The url of the external file.
 * @param {!function(bool, string): void} callback that is sent a bool for
 *     success and the string.
 */
var loadTextFileAsync = function(url, callback) {
  log ("loading: " + url);
  var error = 'loadTextFileAsync failed to load url "' + url + '"';
  var request;
  if (window.XMLHttpRequest) {
    request = new XMLHttpRequest();
    if (request.overrideMimeType) {
      request.overrideMimeType('text/plain');
    }
  } else {
    throw 'XMLHttpRequest is disabled';
  }
  try {
    request.open('GET', url, true);
    request.onreadystatechange = function() {
      if (request.readyState == 4) {
        var text = '';
        // HTTP reports success with a 200 status. The file protocol reports
        // success with zero. HTTP does not use zero as a status code (they
        // start at 100).
        // https://developer.mozilla.org/En/Using_XMLHttpRequest
        var success = request.status == 200 || request.status == 0;
        if (success) {
          text = request.responseText;
          log("completed load request: " + url);
        } else {
          log("loading " + url + " resulted in unexpected status: " + request.status + " " + request.statusText);
        }
        callback(success, text);
      }
    };
    request.onerror = function(errorEvent) {
      log("error occurred loading " + url);
      callback(false, '');
    };
    request.send(null);
  } catch (err) {
    log("failed to load: " + url + " with exception " + err.message);
    callback(false, '');
  }
};

/**
 * Recursively loads a file as a list. Each line is parsed for a relative
 * path. If the file ends in .txt the contents of that file is inserted in
 * the list.
 *
 * @param {string} url The url of the external file.
 * @param {!function(bool, Array<string>): void} callback that is sent a bool
 *     for success and the array of strings.
 */
var getFileListAsync = function(url, callback) {
  var files = [];

  var getFileListImpl = function(url, callback) {
    var files = [];
    if (url.substr(url.length - 4) == '.txt') {
      loadTextFileAsync(url, function() {
        return function(success, text) {
          if (!success) {
            callback(false, '');
            return;
          }
          var lines = text.split('\n');
          var prefix = '';
          var lastSlash = url.lastIndexOf('/');
          if (lastSlash >= 0) {
            prefix = url.substr(0, lastSlash + 1);
          }
          var fail = false;
          var count = 1;
          var index = 0;
          for (var ii = 0; ii < lines.length; ++ii) {
            var str = lines[ii].replace(/^\s\s*/, '').replace(/\s\s*$/, '');
            if (str.length > 4 &&
                str[0] != '#' &&
                str[0] != ";" &&
                str.substr(0, 2) != "//") {
              var names = str.split(/ +/);
              var new_url = prefix + str;
              if (names.length == 1) {
                new_url = prefix + str;
                ++count;
                getFileListImpl(new_url, function(index) {
                  return function(success, new_files) {
                    log("got files: " + new_files.length);
                    if (success) {
                      files[index] = new_files;
                    }
                    finish(success);
                  };
                }(index++));
              } else {
                var s = "";
                var p = "";
                for (var jj = 0; jj < names.length; ++jj) {
                  s += p + prefix + names[jj];
                  p = " ";
                }
                files[index++] = s;
              }
            }
          }
          finish(true);

          function finish(success) {
            if (!success) {
              fail = true;
            }
            --count;
            log("count: " + count);
            if (!count) {
              callback(!fail, files);
            }
          }
        }
      }());

    } else {
      files.push(url);
      callback(true, files);
    }
  };

  getFileListImpl(url, function(success, files) {
    // flatten
    var flat = [];
    flatten(files);
    function flatten(files) {
      for (var ii = 0; ii < files.length; ++ii) {
        var value = files[ii];
        if (typeof(value) == "string") {
          flat.push(value);
        } else {
          flatten(value);
        }
      }
    }
    callback(success, flat);
  });
};

/**
 * Gets a file from a file/URL.
 * @param {string} file the URL of the file to get.
 * @return {string} The contents of the file.
 */
var readFile = function(file) {
  var xhr = new XMLHttpRequest();
  xhr.open("GET", file, false);
  xhr.overrideMimeType("text/plain");
  xhr.send();
  return xhr.responseText.replace(/\r/g, "");
};

var readFileList = function(url) {
  var files = [];
  if (url.substr(url.length - 4) == '.txt') {
    var lines = readFile(url).split('\n');
    var prefix = '';
    var lastSlash = url.lastIndexOf('/');
    if (lastSlash >= 0) {
      prefix = url.substr(0, lastSlash + 1);
    }
    for (var ii = 0; ii < lines.length; ++ii) {
      var str = lines[ii].replace(/^\s\s*/, '').replace(/\s\s*$/, '');
      if (str.length > 4 &&
          str[0] != '#' &&
          str[0] != ";" &&
          str.substr(0, 2) != "//") {
        var names = str.split(/ +/);
        if (names.length == 1) {
          var new_url = prefix + str;
          files = files.concat(readFileList(new_url));
        } else {
          var s = "";
          var p = "";
          for (var jj = 0; jj < names.length; ++jj) {
            s += p + prefix + names[jj];
            p = " ";
          }
          files.push(s);
        }
      }
    }
  } else {
    files.push(url);
  }
  return files;
};

/**
 * Loads a shader.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} shaderSource The shader source.
 * @param {number} shaderType The type of shader.
 * @param {function(string): void} opt_errorCallback callback for errors.
 * @param {boolean} opt_logShaders Whether to log shader source.
 * @param {string} opt_shaderLabel Label that identifies the shader source in
 *     the log.
 * @param {string} opt_url URL from where the shader source was loaded from.
 *     If opt_logShaders is set, then a link to the source file will also be
 *     added.
 * @param {boolean} Skip compilation status check. Default = false.
 * @return {!WebGLShader} The created shader.
 */
var loadShader = function(
    gl, shaderSource, shaderType, opt_errorCallback, opt_logShaders,
    opt_shaderLabel, opt_url, opt_skipCompileStatus) {
  var errFn = opt_errorCallback || error;
  // Create the shader object
  var shader = gl.createShader(shaderType);
  if (shader == null) {
    errFn("*** Error: unable to create shader '"+shaderSource+"'");
    return null;
  }

  // Load the shader source
  gl.shaderSource(shader, shaderSource);

  // Compile the shader
  gl.compileShader(shader);

  if (opt_logShaders) {
    var label = shaderType == gl.VERTEX_SHADER ? 'vertex shader' : 'fragment_shader';
    if (opt_shaderLabel) {
      label = opt_shaderLabel + ' ' + label;
    }
    addShaderSources(
        gl, document.getElementById('console'), label, shader, shaderSource, opt_url);
  }

  // Check the compile status
  if (!opt_skipCompileStatus) {
    var compiled = gl.getShaderParameter(shader, gl.COMPILE_STATUS);
    if (!compiled) {
      // Something went wrong during compilation; get the error
      lastError = gl.getShaderInfoLog(shader);
      errFn("*** Error compiling " + glEnumToString(gl, shaderType) + " '" + shader + "':" + lastError);
      gl.deleteShader(shader);
      return null;
    }
  }

  return shader;
}

/**
 * Loads a shader from a URL.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {file} file The URL of the shader source.
 * @param {number} type The type of shader.
 * @param {function(string): void} opt_errorCallback callback for errors.
 * @param {boolean} opt_logShaders Whether to log shader source.
 * @param {boolean} Skip compilation status check. Default = false.
 * @return {!WebGLShader} The created shader.
 */
var loadShaderFromFile = function(
    gl, file, type, opt_errorCallback, opt_logShaders, opt_skipCompileStatus) {
  var shaderSource = readFile(file);
  return loadShader(gl, shaderSource, type, opt_errorCallback,
      opt_logShaders, undefined, file, opt_skipCompileStatus);
};

var loadShaderFromFileAsync = function(
    gl, file, type, opt_errorCallback, opt_logShaders, opt_skipCompileStatus, callback) {
  loadTextFileAsync(file, function(gl, type, opt_errorCallback, opt_logShaders, file, opt_skipCompileStatus){
      return function(success, shaderSource) {
        if (success) {
          var shader = loadShader(gl, shaderSource, type, opt_errorCallback,
              opt_logShaders, undefined, file, opt_skipCompileStatus);
          callback(true, shader);
        } else {
          callback(false, null);
        }
      }
  }(gl, type, opt_errorCallback, opt_logShaders, file, opt_skipCompileStatus));
};

/**
 * Gets the content of script.
 * @param {string} scriptId The id of the script tag.
 * @return {string} The content of the script.
 */
var getScript = function(scriptId) {
  var shaderScript = document.getElementById(scriptId);
  if (!shaderScript) {
    throw("*** Error: unknown script element " + scriptId);
  }
  return shaderScript.text;
};

/**
 * Loads a shader from a script tag.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} scriptId The id of the script tag.
 * @param {number} opt_shaderType The type of shader. If not passed in it will
 *     be derived from the type of the script tag.
 * @param {function(string): void} opt_errorCallback callback for errors.
 * @param {boolean} opt_logShaders Whether to log shader source.
 * @param {boolean} Skip compilation status check. Default = false.
 * @return {!WebGLShader} The created shader.
 */
var loadShaderFromScript = function(
    gl, scriptId, opt_shaderType, opt_errorCallback, opt_logShaders, opt_skipCompileStatus) {
  var shaderSource = "";
  var shaderScript = document.getElementById(scriptId);
  if (!shaderScript) {
    throw("*** Error: unknown script element " + scriptId);
  }
  shaderSource = shaderScript.text.trim();

  if (!opt_shaderType) {
    if (shaderScript.type == "x-shader/x-vertex") {
      opt_shaderType = gl.VERTEX_SHADER;
    } else if (shaderScript.type == "x-shader/x-fragment") {
      opt_shaderType = gl.FRAGMENT_SHADER;
    } else {
      throw("*** Error: unknown shader type");
      return null;
    }
  }

  return loadShader(gl, shaderSource, opt_shaderType, opt_errorCallback,
      opt_logShaders, undefined, undefined, opt_skipCompileStatus);
};

var loadStandardProgram = function(gl) {
  var program = gl.createProgram();
  gl.attachShader(program, loadStandardVertexShader(gl));
  gl.attachShader(program, loadStandardFragmentShader(gl));
  gl.bindAttribLocation(program, 0, "a_vertex");
  gl.bindAttribLocation(program, 1, "a_normal");
  linkProgram(gl, program);
  return program;
};

var loadStandardProgramAsync = function(gl, callback) {
  loadStandardVertexShaderAsync(gl, function(gl) {
    return function(success, vs) {
      if (success) {
        loadStandardFragmentShaderAsync(gl, function(vs) {
          return function(success, fs) {
            if (success) {
              var program = gl.createProgram();
              gl.attachShader(program, vs);
              gl.attachShader(program, fs);
              gl.bindAttribLocation(program, 0, "a_vertex");
              gl.bindAttribLocation(program, 1, "a_normal");
              linkProgram(gl, program);
              callback(true, program);
            } else {
              callback(false, null);
            }
          };
        }(vs));
      } else {
        callback(false, null);
      }
    };
  }(gl));
};

/**
 * Loads shaders from files, creates a program, attaches the shaders and links.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} vertexShaderPath The URL of the vertex shader.
 * @param {string} fragmentShaderPath The URL of the fragment shader.
 * @param {function(string): void} opt_errorCallback callback for errors.
 * @return {!WebGLProgram} The created program.
 */
var loadProgramFromFile = function(
    gl, vertexShaderPath, fragmentShaderPath, opt_errorCallback) {
  var program = gl.createProgram();
  var vs = loadShaderFromFile(
      gl, vertexShaderPath, gl.VERTEX_SHADER, opt_errorCallback);
  var fs = loadShaderFromFile(
      gl, fragmentShaderPath, gl.FRAGMENT_SHADER, opt_errorCallback);
  if (vs && fs) {
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    linkProgram(gl, program, opt_errorCallback);
  }
  if (vs) {
    gl.deleteShader(vs);
  }
  if (fs) {
    gl.deleteShader(fs);
  }
  return program;
};

/**
 * Loads shaders from script tags, creates a program, attaches the shaders and
 * links.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} vertexScriptId The id of the script tag that contains the
 *        vertex shader.
 * @param {string} fragmentScriptId The id of the script tag that contains the
 *        fragment shader.
 * @param {function(string): void} opt_errorCallback callback for errors.
 * @return {!WebGLProgram} The created program.
 */
var loadProgramFromScript = function loadProgramFromScript(
    gl, vertexScriptId, fragmentScriptId, opt_errorCallback) {
  var program = gl.createProgram();
  gl.attachShader(
      program,
      loadShaderFromScript(
          gl, vertexScriptId, gl.VERTEX_SHADER, opt_errorCallback));
  gl.attachShader(
      program,
      loadShaderFromScript(
          gl, fragmentScriptId,  gl.FRAGMENT_SHADER, opt_errorCallback));
  linkProgram(gl, program, opt_errorCallback);
  return program;
};

/**
 * Loads shaders from source, creates a program, attaches the shaders and
 * links.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!WebGLShader} vertexShader The vertex shader.
 * @param {!WebGLShader} fragmentShader The fragment shader.
 * @param {function(string): void} opt_errorCallback callback for errors.
 * @return {!WebGLProgram} The created program.
 */
var createProgram = function(gl, vertexShader, fragmentShader, opt_errorCallback) {
  var program = gl.createProgram();
  gl.attachShader(program, vertexShader);
  gl.attachShader(program, fragmentShader);
  linkProgram(gl, program, opt_errorCallback);
  return program;
};

/**
 * Loads shaders from source, creates a program, attaches the shaders and
 * links.
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} vertexShader The vertex shader source.
 * @param {string} fragmentShader The fragment shader source.
 * @param {function(string): void} opt_errorCallback callback for errors.
 * @param {boolean} opt_logShaders Whether to log shader source.
 * @return {!WebGLProgram} The created program.
 */
var loadProgram = function(
    gl, vertexShader, fragmentShader, opt_errorCallback, opt_logShaders) {
  var program;
  var vs = loadShader(
      gl, vertexShader, gl.VERTEX_SHADER, opt_errorCallback, opt_logShaders);
  var fs = loadShader(
      gl, fragmentShader, gl.FRAGMENT_SHADER, opt_errorCallback, opt_logShaders);
  if (vs && fs) {
    program = createProgram(gl, vs, fs, opt_errorCallback)
  }
  if (vs) {
    gl.deleteShader(vs);
  }
  if (fs) {
    gl.deleteShader(fs);
  }
  return program;
};

/**
 * Loads shaders from source, creates a program, attaches the shaders and
 * links but expects error.
 *
 * GLSL 1.0.17 10.27 effectively says that compileShader can
 * always succeed as long as linkProgram fails so we can't
 * rely on compileShader failing. This function expects
 * one of the shader to fail OR linking to fail.
 *
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} vertexShaderScriptId The vertex shader.
 * @param {string} fragmentShaderScriptId The fragment shader.
 * @return {WebGLProgram} The created program.
 */
var loadProgramFromScriptExpectError = function(
    gl, vertexShaderScriptId, fragmentShaderScriptId) {
  var vertexShader = loadShaderFromScript(gl, vertexShaderScriptId);
  if (!vertexShader) {
    return null;
  }
  var fragmentShader = loadShaderFromScript(gl, fragmentShaderScriptId);
  if (!fragmentShader) {
    return null;
  }
  var linkSuccess = true;
  var program = gl.createProgram();
  gl.attachShader(program, vertexShader);
  gl.attachShader(program, fragmentShader);
  linkSuccess = true;
  linkProgram(gl, program, function() {
      linkSuccess = false;
    });
  return linkSuccess ? program : null;
};


var getActiveMap = function(gl, program, typeInfo) {
  var numVariables = gl.getProgramParameter(program, gl[typeInfo.param]);
  var variables = {};
  for (var ii = 0; ii < numVariables; ++ii) {
    var info = gl[typeInfo.activeFn](program, ii);
    variables[info.name] = {
      name: info.name,
      size: info.size,
      type: info.type,
      location: gl[typeInfo.locFn](program, info.name)
    };
  }
  return variables;
};

/**
 * Returns a map of attrib names to info about those
 * attribs.
 *
 * eg:
 *    { "attrib1Name":
 *      {
 *        name: "attrib1Name",
 *        size: 1,
 *        type: gl.FLOAT_MAT2,
 *        location: 0
 *      },
 *      "attrib2Name[0]":
 *      {
 *         name: "attrib2Name[0]",
 *         size: 4,
 *         type: gl.FLOAT,
 *         location: 1
 *      },
 *    }
 *
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {WebGLProgram} The program to query for attribs.
 * @return the map.
 */
var getAttribMap = function(gl, program) {
  return getActiveMap(gl, program, {
      param: "ACTIVE_ATTRIBUTES",
      activeFn: "getActiveAttrib",
      locFn: "getAttribLocation"
  });
};

/**
 * Returns a map of uniform names to info about those uniforms.
 *
 * eg:
 *    { "uniform1Name":
 *      {
 *        name: "uniform1Name",
 *        size: 1,
 *        type: gl.FLOAT_MAT2,
 *        location: WebGLUniformLocation
 *      },
 *      "uniform2Name[0]":
 *      {
 *         name: "uniform2Name[0]",
 *         size: 4,
 *         type: gl.FLOAT,
 *         location: WebGLUniformLocation
 *      },
 *    }
 *
 * @param {!WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {WebGLProgram} The program to query for uniforms.
 * @return the map.
 */
var getUniformMap = function(gl, program) {
  return getActiveMap(gl, program, {
      param: "ACTIVE_UNIFORMS",
      activeFn: "getActiveUniform",
      locFn: "getUniformLocation"
  });
};

var basePath;
var getResourcePath = function() {
  if (!basePath) {
    var expectedBase = "js/webgl-test-utils.js";
    var scripts = document.getElementsByTagName('script');
    for (var script, i = 0; script = scripts[i]; i++) {
      var src = script.src;
      var l = src.length;
      if (src.substr(l - expectedBase.length) == expectedBase) {
        basePath = src.substr(0, l - expectedBase.length);
      }
    }
  }
  return basePath + "resources/";
};

var loadStandardVertexShader = function(gl) {
  return loadShaderFromFile(
      gl, getResourcePath() + "vertexShader.vert", gl.VERTEX_SHADER);
};
var loadStandardVertexShaderAsync = function(gl, callback) {
  loadShaderFromFileAsync(gl, getResourcePath() + "vertexShader.vert", gl.VERTEX_SHADER, undefined, undefined, undefined, callback);
};

var loadStandardFragmentShader = function(gl) {
  return loadShaderFromFile(
      gl, getResourcePath() + "fragmentShader.frag", gl.FRAGMENT_SHADER);
};
var loadStandardFragmentShaderAsync = function(gl, callback) {
  loadShaderFromFileAsync(gl, getResourcePath() + "fragmentShader.frag", gl.FRAGMENT_SHADER, undefined, undefined, undefined, callback);
};

var loadUniformBlockProgram = function(gl) {
  var program = gl.createProgram();
  gl.attachShader(program, loadUniformBlockVertexShader(gl));
  gl.attachShader(program, loadUniformBlockFragmentShader(gl));
  gl.bindAttribLocation(program, 0, "a_vertex");
  gl.bindAttribLocation(program, 1, "a_normal");
  linkProgram(gl, program);
  return program;
};

var loadUniformBlockVertexShader = function(gl) {
  return loadShaderFromFile(
      gl, getResourcePath() + "uniformBlockShader.vert", gl.VERTEX_SHADER);
};

var loadUniformBlockFragmentShader = function(gl) {
  return loadShaderFromFile(
      gl, getResourcePath() + "uniformBlockShader.frag", gl.FRAGMENT_SHADER);
};

/**
 * Loads an image asynchronously.
 * @param {string} url URL of image to load.
 * @param {!function(!Element): void} callback Function to call
 *     with loaded image.
 */
var loadImageAsync = function(url, callback) {
  var img = document.createElement('img');
  img.onload = function() {
    callback(img);
  };
  img.src = url;
};

/**
 * Loads an array of images.
 * @param {!Array.<string>} urls URLs of images to load.
 * @param {!function(!{string, img}): void} callback Callback
 *     that gets passed map of urls to img tags.
 */
var loadImagesAsync = function(urls, callback) {
  var count = 1;
  var images = { };
  function countDown() {
    --count;
    if (count == 0) {
      log("loadImagesAsync: all images loaded");
      callback(images);
    }
  }
  function imageLoaded(url) {
    return function(img) {
      images[url] = img;
      log("loadImagesAsync: loaded " + url);
      countDown();
    }
  }
  for (var ii = 0; ii < urls.length; ++ii) {
    ++count;
    loadImageAsync(urls[ii], imageLoaded(urls[ii]));
  }
  countDown();
};

/**
 * Returns a map of key=value values from url.
 * @return {!Object.<string, number>} map of keys to values.
 */
var getUrlArguments = function() {
  var args = {};
  try {
    var s = window.location.href;
    var q = s.indexOf("?");
    var e = s.indexOf("#");
    if (e < 0) {
      e = s.length;
    }
    var query = s.substring(q + 1, e);
    var pairs = query.split("&");
    for (var ii = 0; ii < pairs.length; ++ii) {
      var keyValue = pairs[ii].split("=");
      var key = keyValue[0];
      var value = decodeURIComponent(keyValue[1]);
      args[key] = value;
    }
  } catch (e) {
    throw "could not parse url";
  }
  return args;
};

/**
 * Makes an image from a src.
 * @param {string} src Image source URL.
 * @param {function()} onload Callback to call when the image has finised loading.
 * @param {function()} onerror Callback to call when an error occurs.
 * @return {!Image} The created image.
 */
var makeImage = function(src, onload, onerror) {
  var img = document.createElement('img');
  if (onload) {
    img.onload = onload;
  }
  if (onerror) {
    img.onerror = onerror;
  } else {
    img.onerror = function() {
      log("WARNING: creating image failed; src: " + this.src);
    };
  }
  if (src) {
    img.src = src;
  }
  return img;
}

/**
 * Makes an image element from a canvas.
 * @param {!HTMLCanvas} canvas Canvas to make image from.
 * @param {function()} onload Callback to call when the image has finised loading.
 * @param {string} imageFormat Image format to be passed to toDataUrl().
 * @return {!Image} The created image.
 */
var makeImageFromCanvas = function(canvas, onload, imageFormat) {
  return makeImage(canvas.toDataURL(imageFormat), onload);
};

/**
 * Makes a video element from a src.
 * @param {string} src Video source URL.
 * @param {function()} onerror Callback to call when an error occurs.
 * @return {!Video} The created video.
 */
var makeVideo = function(src, onerror) {
  var vid = document.createElement('video');
  vid.muted = true;
  if (onerror) {
    vid.onerror = onerror;
  } else {
    vid.onerror = function() {
      log("WARNING: creating video failed; src: " + this.src);
    };
  }
  if (src) {
    vid.src = src;
  }
  return vid;
}

/**
 * Inserts an image with a caption into 'element'.
 * @param {!HTMLElement} element Element to append image to.
 * @param {string} caption caption to associate with image.
 * @param {!Image} img image to insert.
 */
var insertImage = function(element, caption, img) {
  var div = document.createElement("div");
  var label = document.createElement("div");
  label.appendChild(document.createTextNode(caption));
  div.appendChild(label);
  div.appendChild(img);
  element.appendChild(div);
};

/**
 * Inserts a 'label' that when clicked expands to the pre formatted text
 * supplied by 'source'.
 * @param {!HTMLElement} element element to append label to.
 * @param {string} label label for anchor.
 * @param {string} source preformatted text to expand to.
 * @param {string} opt_url URL of source. If provided a link to the source file
 *     will also be added.
 */
var addShaderSource = function(element, label, source, opt_url) {
  var div = document.createElement("div");
  var s = document.createElement("pre");
  s.className = "shader-source";
  s.style.display = "none";
  var ol = document.createElement("ol");
  //s.appendChild(document.createTextNode(source));
  var lines = source.split("\n");
  for (var ii = 0; ii < lines.length; ++ii) {
    var line = lines[ii];
    var li = document.createElement("li");
    li.appendChild(document.createTextNode(line));
    ol.appendChild(li);
  }
  s.appendChild(ol);
  var l = document.createElement("a");
  l.href = "show-shader-source";
  l.appendChild(document.createTextNode(label));
  l.addEventListener('click', function(event) {
      if (event.preventDefault) {
        event.preventDefault();
      }
      s.style.display = (s.style.display == 'none') ? 'block' : 'none';
      return false;
    }, false);
  div.appendChild(l);
  if (opt_url) {
    var u = document.createElement("a");
    u.href = opt_url;
    div.appendChild(document.createTextNode(" "));
    u.appendChild(document.createTextNode("(" + opt_url + ")"));
    div.appendChild(u);
  }
  div.appendChild(s);
  element.appendChild(div);
};

/**
 * Inserts labels that when clicked expand to show the original source of the
 * shader and also translated source of the shader, if that is available.
 * @param {WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {!HTMLElement} element element to append label to.
 * @param {string} label label for anchor.
 * @param {WebGLShader} shader Shader to show the sources for.
 * @param {string} shaderSource Original shader source.
 * @param {string} opt_url URL of source. If provided a link to the source file
 *     will also be added.
 */
var addShaderSources = function(
    gl, element, label, shader, shaderSource, opt_url) {
  addShaderSource(element, label, shaderSource, opt_url);

  var debugShaders = gl.getExtension('WEBGL_debug_shaders');
  if (debugShaders && shader) {
    var translatedSource = debugShaders.getTranslatedShaderSource(shader);
    if (translatedSource != '') {
      addShaderSource(element, label + ' translated for driver', translatedSource);
    }
  }
};

/**
 * Sends shader information to the server to be dumped into text files
 * when tests are run from within the test-runner harness.
 * @param {WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} url URL of current.
 * @param {string} passMsg Test description.
 * @param {object} vInfo Object containing vertex shader information.
 * @param {object} fInfo Object containing fragment shader information.
 */
var dumpShadersInfo = function(gl, url, passMsg, vInfo, fInfo) {
  var shaderInfo = {};
  shaderInfo.url = url;
  shaderInfo.testDescription = passMsg;
  shaderInfo.vLabel = vInfo.label;
  shaderInfo.vShouldCompile = vInfo.shaderSuccess;
  shaderInfo.vSource = vInfo.source;
  shaderInfo.fLabel = fInfo.label;
  shaderInfo.fShouldCompile = fInfo.shaderSuccess;
  shaderInfo.fSource = fInfo.source;
  shaderInfo.vTranslatedSource = null;
  shaderInfo.fTranslatedSource = null;
  var debugShaders = gl.getExtension('WEBGL_debug_shaders');
  if (debugShaders) {
    if (vInfo.shader)
      shaderInfo.vTranslatedSource = debugShaders.getTranslatedShaderSource(vInfo.shader);
    if (fInfo.shader)
      shaderInfo.fTranslatedSource = debugShaders.getTranslatedShaderSource(fInfo.shader);
  }

  var dumpShaderInfoRequest = new XMLHttpRequest();
  dumpShaderInfoRequest.open('POST', "/dumpShaderInfo", true);
  dumpShaderInfoRequest.setRequestHeader("Content-Type", "text/plain");
  dumpShaderInfoRequest.send(JSON.stringify(shaderInfo));
};

// Add your prefix here.
var browserPrefixes = [
  "",
  "MOZ_",
  "OP_",
  "WEBKIT_"
];

/**
 * Given an extension name like WEBGL_compressed_texture_s3tc
 * returns the name of the supported version extension, like
 * WEBKIT_WEBGL_compressed_teture_s3tc
 * @param {string} name Name of extension to look for.
 * @return {string} name of extension found or undefined if not
 *     found.
 */
var getSupportedExtensionWithKnownPrefixes = function(gl, name) {
  var supported = gl.getSupportedExtensions();
  for (var ii = 0; ii < browserPrefixes.length; ++ii) {
    var prefixedName = browserPrefixes[ii] + name;
    if (supported.indexOf(prefixedName) >= 0) {
      return prefixedName;
    }
  }
};

/**
 * @param {WebGLRenderingContext} gl The WebGLRenderingContext to use.
 * @param {string} name Name of extension to look for.
 * @param {boolean} extensionEnabled True if the extension was enabled successfully via gl.getExtension().
 */
var runExtensionSupportedTest = function(gl, name, extensionEnabled) {
  var prefixedName = getSupportedExtensionWithKnownPrefixes(gl, name);
  if (prefixedName !== undefined) {
      if (extensionEnabled) {
          testPassed(name + " listed as supported and getExtension succeeded");
      } else {
          testFailed(name + " listed as supported but getExtension failed");
      }
  } else {
      if (extensionEnabled) {
          testFailed(name + " not listed as supported but getExtension succeeded");
      } else {
          testPassed(name + " not listed as supported and getExtension failed -- this is legal");
      }
  }
}

/**
 * Given an extension name like WEBGL_compressed_texture_s3tc
 * returns the supported version extension, like
 * WEBKIT_WEBGL_compressed_teture_s3tc
 * @param {string} name Name of extension to look for.
 * @return {WebGLExtension} The extension or undefined if not
 *     found.
 */
var getExtensionWithKnownPrefixes = function(gl, name) {
  for (var ii = 0; ii < browserPrefixes.length; ++ii) {
    var prefixedName = browserPrefixes[ii] + name;
    var ext = gl.getExtension(prefixedName);
    if (ext) {
      return ext;
    }
  }
};

/**
 * Returns possible prefixed versions of an extension's name.
 * @param {string} name Name of extension. May already include a prefix.
 * @return {Array.<string>} Variations of the extension name with known
 *     browser prefixes.
 */
var getExtensionPrefixedNames = function(name) {
  var unprefix = function(name) {
    for (var ii = 0; ii < browserPrefixes.length; ++ii) {
      if (browserPrefixes[ii].length > 0 &&
          name.substring(0, browserPrefixes[ii].length).toLowerCase() ===
          browserPrefixes[ii].toLowerCase()) {
        return name.substring(browserPrefixes[ii].length);
      }
    }
    return name;
  }

  var unprefixed = unprefix(name);

  var variations = [];
  for (var ii = 0; ii < browserPrefixes.length; ++ii) {
    variations.push(browserPrefixes[ii] + unprefixed);
  }

  return variations;
};

var replaceRE = /\$\((\w+)\)/g;

/**
 * Replaces strings with property values.
 * Given a string like "hello $(first) $(last)" and an object
 * like {first:"John", last:"Smith"} will return
 * "hello John Smith".
 * @param {string} str String to do replacements in.
 * @param {...} 1 or more objects containing properties.
 */
var replaceParams = function(str) {
  var args = arguments;
  return str.replace(replaceRE, function(str, p1, offset, s) {
    for (var ii = 1; ii < args.length; ++ii) {
      if (args[ii][p1] !== undefined) {
        return args[ii][p1];
      }
    }
    throw "unknown string param '" + p1 + "'";
  });
};

var upperCaseFirstLetter = function(str) {
  return str.substring(0, 1).toUpperCase() + str.substring(1);
};

/**
 * Gets a prefixed property. For example,
 *
 *     var fn = getPrefixedProperty(
 *        window,
 *        "requestAnimationFrame");
 *
 * Will return either:
 *    "window.requestAnimationFrame",
 *    "window.oRequestAnimationFrame",
 *    "window.msRequestAnimationFrame",
 *    "window.mozRequestAnimationFrame",
 *    "window.webKitRequestAnimationFrame",
 *    undefined
 *
 * the non-prefixed function is tried first.
 */
var propertyPrefixes = ["", "moz", "ms", "o", "webkit"];
var getPrefixedProperty = function(obj, propertyName) {
  for (var ii = 0; ii < propertyPrefixes.length; ++ii) {
    var prefix = propertyPrefixes[ii];
    var name = prefix + propertyName;
    log(name);
    var property = obj[name];
    if (property) {
      return property;
    }
    if (ii == 0) {
      propertyName = upperCaseFirstLetter(propertyName);
    }
  }
  return undefined;
};

var _requestAnimFrame;

/**
 * Provides requestAnimationFrame in a cross browser way.
 */
var requestAnimFrame = function(callback) {
  if (!_requestAnimFrame) {
    _requestAnimFrame = getPrefixedProperty(window, "requestAnimationFrame") ||
      function(callback, element) {
        return window.setTimeout(callback, 1000 / 70);
      };
  }
  _requestAnimFrame.call(window, callback);
};

var _cancelAnimFrame;

/**
 * Provides cancelAnimationFrame in a cross browser way.
 */
var cancelAnimFrame = function(request) {
  if (!_cancelAnimFrame) {
    _cancelAnimFrame = getPrefixedProperty(window, "cancelAnimationFrame") ||
      window.clearTimeout;
  }
  _cancelAnimFrame.call(window, request);
};

/**
 * Provides requestFullScreen in a cross browser way.
 */
var requestFullScreen = function(element) {
  var fn = getPrefixedProperty(element, "requestFullScreen");
  if (fn) {
    fn.call(element);
  }
};

/**
 * Provides cancelFullScreen in a cross browser way.
 */
var cancelFullScreen = function() {
  var fn = getPrefixedProperty(document, "cancelFullScreen");
  if (fn) {
    fn.call(document);
  }
};

var fullScreenStateName;
(function() {
  var fullScreenStateNames = [
    "isFullScreen",
    "fullScreen"
  ];
  for (var ii = 0; ii < fullScreenStateNames.length; ++ii) {
    var propertyName = fullScreenStateNames[ii];
    for (var jj = 0; jj < propertyPrefixes.length; ++jj) {
      var prefix = propertyPrefixes[jj];
      if (prefix.length) {
        propertyName = upperCaseFirstLetter(propertyName);
        fullScreenStateName = prefix + propertyName;
        if (document[fullScreenStateName] !== undefined) {
          return;
        }
      }
    }
    fullScreenStateName = undefined;
  }
}());

/**
 * @return {boolean} True if fullscreen mode is active.
 */
var getFullScreenState = function() {
  log("fullscreenstatename:" + fullScreenStateName);
  log(document[fullScreenStateName]);
  return document[fullScreenStateName];
};

/**
 * @param {!HTMLElement} element The element to go fullscreen.
 * @param {!function(boolean)} callback A function that will be called
 *        when entering/exiting fullscreen. It is passed true if
 *        entering fullscreen, false if exiting.
 */
var onFullScreenChange = function(element, callback) {
  propertyPrefixes.forEach(function(prefix) {
    var eventName = prefix + "fullscreenchange";
    log("addevent: " + eventName);
    document.addEventListener(eventName, function(event) {
      log("event: " + eventName);
      callback(getFullScreenState());
    });
  });
};

/**
 * @param {!string} buttonId The id of the button that will toggle fullscreen
 *        mode.
 * @param {!string} fullscreenId The id of the element to go fullscreen.
 * @param {!function(boolean)} callback A function that will be called
 *        when entering/exiting fullscreen. It is passed true if
 *        entering fullscreen, false if exiting.
 * @return {boolean} True if fullscreen mode is supported.
 */
var setupFullscreen = function(buttonId, fullscreenId, callback) {
  if (!fullScreenStateName) {
    return false;
  }

  var fullscreenElement = document.getElementById(fullscreenId);
  onFullScreenChange(fullscreenElement, callback);

  var toggleFullScreen = function(event) {
    if (getFullScreenState()) {
      cancelFullScreen(fullscreenElement);
    } else {
      requestFullScreen(fullscreenElement);
    }
    event.preventDefault();
    return false;
  };

  var buttonElement = document.getElementById(buttonId);
  buttonElement.addEventListener('click', toggleFullScreen);

  return true;
};

/**
 * Waits for the browser to composite the web page.
 * @param {function()} callback A function to call after compositing has taken
 *        place.
 */
var waitForComposite = function(callback) {
  var frames = 5;
  var countDown = function() {
    if (frames == 0) {
      // TODO(kbr): unify with js-test-pre.js and enable these with
      // verbose logging.
      // log("waitForComposite: callback");
      callback();
    } else {
      // log("waitForComposite: countdown(" + frames + ")");
      --frames;
      requestAnimFrame.call(window, countDown);
    }
  };
  countDown();
};

var setZeroTimeout = (function() {
  // See https://dbaron.org/log/20100309-faster-timeouts

  var timeouts = [];
  var messageName = "zero-timeout-message";

  // Like setTimeout, but only takes a function argument.  There's
  // no time argument (always zero) and no arguments (you have to
  // use a closure).
  function setZeroTimeout(fn) {
      timeouts.push(fn);
      window.postMessage(messageName, "*");
  }

  function handleMessage(event) {
      if (event.source == window && event.data == messageName) {
          event.stopPropagation();
          if (timeouts.length > 0) {
              var fn = timeouts.shift();
              fn();
          }
      }
  }

  window.addEventListener("message", handleMessage, true);

  return setZeroTimeout;
})();

function dispatchPromise(fn) {
  return new Promise((fn_resolve, fn_reject) => {
    setZeroTimeout(() => {
      let val;
      if (fn) {
        val = fn();
      }
      fn_resolve(val);
    });
  });
}

/**
 * Runs an array of functions, yielding to the browser between each step.
 * If you want to know when all the steps are finished add a last step.
 * @param {!Array.<function(): void>} steps Array of functions.
 */
var runSteps = function(steps) {
  if (!steps.length) {
    return;
  }

  // copy steps so they can't be modifed.
  var stepsToRun = steps.slice();
  var currentStep = 0;
  var runNextStep = function() {
    stepsToRun[currentStep++]();
    if (currentStep < stepsToRun.length) {
      setTimeout(runNextStep, 1);
    }
  };
  runNextStep();
};

/**
 * Starts playing a video and waits for it to be consumable.
 * @param {!HTMLVideoElement} video An HTML5 Video element.
 * @param {!function(!HTMLVideoElement): void} callback Function to call when
 *        video is ready.
 */
async function startPlayingAndWaitForVideo(video, callback) {
  if (video.error) {
    testFailed('Video failed to load: ' + video.error);
    return;
  }

  video.loop = true;
  video.muted = true;
  // See whether setting the preload flag de-flakes video-related tests.
  video.preload = 'auto';

  try {
    await video.play();
  } catch (e) {
    testFailed('video.play failed: ' + e);
    return;
  }

  if (video.requestVideoFrameCallback) {
    await new Promise(go => video.requestVideoFrameCallback(go));
  }

  callback(video);
}

var getHost = function(url) {
  url = url.replace("\\", "/");
  var pos = url.indexOf("://");
  if (pos >= 0) {
    url = url.substr(pos + 3);
  }
  var parts = url.split('/');
  return parts[0];
}

// This function returns the last 2 words of the domain of a URL
// This is probably not the correct check but it will do for now.
var getBaseDomain = function(host) {
  var parts = host.split(":");
  var hostname = parts[0];
  var port = parts[1] || "80";
  parts = hostname.split(".");
  if(parts.length < 2)
    return hostname + ":" + port;
  var tld = parts[parts.length-1];
  var domain = parts[parts.length-2];
  return domain + "." + tld + ":" + port;
}

var runningOnLocalhost = function() {
  let hostname = window.location.hostname;
  return hostname == "localhost" ||
    hostname == "127.0.0.1" ||
    hostname == "::1";
}

var getLocalCrossOrigin = function() {
  var domain;
  if (window.location.host.indexOf("localhost") != -1) {
    // TODO(kbr): figure out whether to use an IPv6 loopback address.
    domain = "127.0.0.1";
  } else {
    domain = "localhost";
  }

  var port = window.location.port || "80";
  return window.location.protocol + "//" + domain + ":" + port
}

var getRelativePath = function(path) {
  var relparts = window.location.pathname.split("/");
  relparts.pop(); // Pop off filename
  var pathparts = path.split("/");

  var i;
  for (i = 0; i < pathparts.length; ++i) {
    switch (pathparts[i]) {
      case "": break;
      case ".": break;
      case "..":
        relparts.pop();
        break;
      default:
        relparts.push(pathparts[i]);
        break;
    }
  }

  return relparts.join("/");
}

async function loadCrossOriginImage(img, webUrl, localUrl) {
  if (runningOnLocalhost()) {
    img.src = getLocalCrossOrigin() + getRelativePath(localUrl);
    console.log('[loadCrossOriginImage]', '  trying', img.src);
    await img.decode();
    return;
  }

  try {
    img.src = getUrlOptions().imgUrl || webUrl;
    console.log('[loadCrossOriginImage]', 'trying', img.src);
    await img.decode();
    return;
  } catch {}

  throw 'createCrossOriginImage failed';
}

/**
 * Convert sRGB color to linear color.
 * @param {!Array.<number>} color The color to be converted.
 *        The array has 4 elements, for example [R, G, B, A].
 *        where each element is in the range 0 to 255.
 * @return {!Array.<number>} color The color to be converted.
 *        The array has 4 elements, for example [R, G, B, A].
 *        where each element is in the range 0 to 255.
 */
var sRGBToLinear = function(color) {
    return [sRGBChannelToLinear(color[0]),
            sRGBChannelToLinear(color[1]),
            sRGBChannelToLinear(color[2]),
            color[3]]
}

/**
 * Convert linear color to sRGB color.
 * @param {!Array.<number>} color The color to be converted.
 *        The array has 4 elements, for example [R, G, B, A].
 *        where each element is in the range 0 to 255.
 * @return {!Array.<number>} color The color to be converted.
 *        The array has 4 elements, for example [R, G, B, A].
 *        where each element is in the range 0 to 255.
 */
var linearToSRGB = function(color) {
    return [linearChannelToSRGB(color[0]),
            linearChannelToSRGB(color[1]),
            linearChannelToSRGB(color[2]),
            color[3]]
}

function sRGBChannelToLinear(value) {
    value = value / 255;
    if (value <= 0.04045)
        value = value / 12.92;
    else
        value = Math.pow((value + 0.055) / 1.055, 2.4);
    return Math.trunc(value * 255 + 0.5);
}

function linearChannelToSRGB(value) {
    value = value / 255;
    if (value <= 0.0) {
        value = 0.0;
    } else if (value < 0.0031308) {
        value = value * 12.92;
    } else if (value < 1) {
        value = Math.pow(value, 0.41666) * 1.055 - 0.055;
    } else {
        value = 1.0;
    }
    return Math.trunc(value * 255 + 0.5);
}

/**
 * Return the named color in the specified color space.
 * @param {string} colorName The name of the color to convert.
 *        Supported color names are:
 *            'Red', which is the CSS color color('srgb' 1 0 0 1)
 *            'Green', which is the CSS color color('srgb' 0 1 0 1)
 * @param {string} colorSpace The color space to convert to. Supported
          color spaces are:
 *            null, which is treated as sRGB
 *            'srgb'
 *            'display-p3'.
 *        Documentation on the formulas for color conversion between
 *        spaces can be found at
              https://www.w3.org/TR/css-color-4/#predefined-to-predefined
 * @return {!Array.<number>} color The color in the specified color
 *        space as an 8-bit RGBA array with unpremultiplied alpha.
 */
var namedColorInColorSpace = function(colorName, colorSpace) {
  var result;
  switch (colorSpace) {
    case undefined:
    case 'srgb':
      switch(colorName) {
        case 'Red':
          return [255, 0, 0, 255];
        case 'Green':
          return [0, 255, 0, 255];
          break;
        default:
          throw 'unexpected color name: ' + colorName;
      };
      break;
    case 'display-p3':
      switch(colorName) {
        case 'Red':
          return [234, 51, 35, 255];
          break;
        case 'Green':
          return [117, 251, 76, 255];
          break;
        default:
          throw 'unexpected color name: ' + colorName;
      }
      break;
    default:
      throw 'unexpected color space: ' + colorSpace;
  }
}

/**
 * Return the named color as it would be sampled with the specified
 * internal format
 * @param {!Array.<number>} color The color as an 8-bit RGBA array.
 * @param {string} internalformat The internal format.
 * @return {!Array.<number>} color The color, as it would be sampled by
 *        the specified internal format, as an 8-bit RGBA array.
 */
var colorAsSampledWithInternalFormat = function(color, internalFormat) {
  switch (internalFormat) {
    case 'ALPHA':
      return [0, 0, 0, color[3]];
    case 'LUMINANCE':
      return [color[0], color[0], color[0], 255];
    case 'LUMINANCE_ALPHA':
      return [color[0], color[0], color[0], color[3]];
    case 'SRGB8':
    case 'SRGB8_ALPHA8':
      return [sRGBChannelToLinear(color[0]),
              sRGBChannelToLinear(color[1]),
              sRGBChannelToLinear(color[2]),
              color[3]];
    case 'R16F':
    case 'R32F':
    case 'R8':
    case 'R8UI':
    case 'RED':
    case 'RED_INTEGER':
      return [color[0], 0, 0, 0];
    case 'RG':
    case 'RG16F':
    case 'RG32F':
    case 'RG8':
    case 'RG8UI':
    case 'RG_INTEGER':
      return [color[0], color[1], 0, 0];
      break;
    default:
      break;
  }
  return color;
}

function comparePixels(cmp, ref, tolerance, diff) {
    if (cmp.length != ref.length) {
        testFailed("invalid pixel size.");
    }

    var count = 0;
    for (var i = 0; i < cmp.length; i++) {
        if (diff) {
            diff[i * 4] = 0;
            diff[i * 4 + 1] = 255;
            diff[i * 4 + 2] = 0;
            diff[i * 4 + 3] = 255;
        }
        if (Math.abs(cmp[i * 4] - ref[i * 4]) > tolerance ||
            Math.abs(cmp[i * 4 + 1] - ref[i * 4 + 1]) > tolerance ||
            Math.abs(cmp[i * 4 + 2] - ref[i * 4 + 2]) > tolerance ||
            Math.abs(cmp[i * 4 + 3] - ref[i * 4 + 3]) > tolerance) {
            if (count < 10) {
                testFailed("Pixel " + i + ": expected (" +
                [ref[i * 4], ref[i * 4 + 1], ref[i * 4 + 2], ref[i * 4 + 3]] + "), got (" +
                [cmp[i * 4], cmp[i * 4 + 1], cmp[i * 4 + 2], cmp[i * 4 + 3]] + ")");
            }
            count++;
            if (diff) {
                diff[i * 4] = 255;
                diff[i * 4 + 1] = 0;
            }
        }
    }

    return count;
}

function destroyContext(gl) {
  const ext = gl.getExtension('WEBGL_lose_context');
  if (ext) {
    ext.loseContext();
  }
  gl.canvas.width = 1;
  gl.canvas.height = 1;
}

function destroyAllContexts() {
  if (!window._wtu_contexts)
    return;
  for (const x of window._wtu_contexts) {
    destroyContext(x);
  }
  window._wtu_contexts = [];
}

function displayImageDiff(cmp, ref, diff, width, height) {
    var div = document.createElement("div");

    var cmpImg = createImageFromPixel(cmp, width, height);
    var refImg = createImageFromPixel(ref, width, height);
    var diffImg = createImageFromPixel(diff, width, height);
    wtu.insertImage(div, "Reference", refImg);
    wtu.insertImage(div, "Result", cmpImg);
    wtu.insertImage(div, "Difference", diffImg);

    var console = document.getElementById("console");
    console.appendChild(div);
}

function createImageFromPixel(buf, width, height) {
    var canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    var ctx = canvas.getContext("2d");
    var imgData = ctx.getImageData(0, 0, width, height);

    for (var i = 0; i < buf.length; i++)
        imgData.data[i] = buf[i];
    ctx.putImageData(imgData, 0, 0);
    var img = wtu.makeImageFromCanvas(canvas);
    return img;
}

async function awaitTimeout(ms) {
  await new Promise(res => {
    setTimeout(() => {
      res();
    }, ms);
  });
}

async function awaitOrTimeout(promise, opt_timeout_ms) {
  async function throwOnTimeout(ms) {
    await awaitTimeout(ms);
    throw 'timeout';
  }

  let timeout_ms = opt_timeout_ms;
  if (timeout_ms === undefined)
    timeout_ms = 5000;

  await Promise.race([promise, throwOnTimeout(timeout_ms)]);
}

var API = {
  addShaderSource: addShaderSource,
  addShaderSources: addShaderSources,
  cancelAnimFrame: cancelAnimFrame,
  create3DContext: create3DContext,
  GLErrorException: GLErrorException,
  create3DContextWithWrapperThatThrowsOnGLError: create3DContextWithWrapperThatThrowsOnGLError,
  checkAreaInAndOut: checkAreaInAndOut,
  checkCanvas: checkCanvas,
  checkCanvasRect: checkCanvasRect,
  checkCanvasRectColor: checkCanvasRectColor,
  checkCanvasRects: checkCanvasRects,
  checkFloatBuffer: checkFloatBuffer,
  checkTextureSize: checkTextureSize,
  clipToRange: clipToRange,
  createColoredTexture: createColoredTexture,
  createProgram: createProgram,
  clearAndDrawUnitQuad: clearAndDrawUnitQuad,
  clearAndDrawIndexedQuad: clearAndDrawIndexedQuad,
  comparePixels: comparePixels,
  destroyAllContexts: destroyAllContexts,
  destroyContext: destroyContext,
  dispatchPromise: dispatchPromise,
  displayImageDiff: displayImageDiff,
  drawUnitQuad: drawUnitQuad,
  drawIndexedQuad: drawIndexedQuad,
  drawUByteColorQuad: drawUByteColorQuad,
  drawFloatColorQuad: drawFloatColorQuad,
  dummySetProgramAndDrawNothing: dummySetProgramAndDrawNothing,
  dumpShadersInfo: dumpShadersInfo,
  endsWith: endsWith,
  failIfGLError: failIfGLError,
  fillTexture: fillTexture,
  framebufferStatusShouldBe: framebufferStatusShouldBe,
  getBytesPerComponent: getBytesPerComponent,
  getDefault3DContextVersion: getDefault3DContextVersion,
  getExtensionPrefixedNames: getExtensionPrefixedNames,
  getExtensionWithKnownPrefixes: getExtensionWithKnownPrefixes,
  getFileListAsync: getFileListAsync,
  getLastError: getLastError,
  getPrefixedProperty: getPrefixedProperty,
  getScript: getScript,
  getSupportedExtensionWithKnownPrefixes: getSupportedExtensionWithKnownPrefixes,
  getTypedArrayElementsPerPixel: getTypedArrayElementsPerPixel,
  getUrlArguments: getUrlArguments,
  getUrlOptions: getUrlOptions,
  getAttribMap: getAttribMap,
  getUniformMap: getUniformMap,
  glEnumToString: glEnumToString,
  glErrorAssert: glErrorAssert,
  glErrorShouldBe: glErrorShouldBe,
  glTypeToTypedArrayType: glTypeToTypedArrayType,
  hasAttributeCaseInsensitive: hasAttributeCaseInsensitive,
  insertImage: insertImage,
  isWebGL2: isWebGL2,
  linkProgram: linkProgram,
  loadCrossOriginImage: loadCrossOriginImage,
  loadImageAsync: loadImageAsync,
  loadImagesAsync: loadImagesAsync,
  loadProgram: loadProgram,
  loadProgramFromFile: loadProgramFromFile,
  loadProgramFromScript: loadProgramFromScript,
  loadProgramFromScriptExpectError: loadProgramFromScriptExpectError,
  loadShader: loadShader,
  loadShaderFromFile: loadShaderFromFile,
  loadShaderFromScript: loadShaderFromScript,
  loadStandardProgram: loadStandardProgram,
  loadStandardProgramAsync: loadStandardProgramAsync,
  loadStandardVertexShader: loadStandardVertexShader,
  loadStandardVertexShaderAsync: loadStandardVertexShaderAsync,
  loadStandardFragmentShader: loadStandardFragmentShader,
  loadStandardFragmentShaderAsync: loadStandardFragmentShaderAsync,
  loadUniformBlockProgram: loadUniformBlockProgram,
  loadUniformBlockVertexShader: loadUniformBlockVertexShader,
  loadUniformBlockFragmentShader: loadUniformBlockFragmentShader,
  loadTextFileAsync: loadTextFileAsync,
  loadTexture: loadTexture,
  log: log,
  loggingOff: loggingOff,
  makeCheckRect: makeCheckRect,
  makeImage: makeImage,
  makeImageFromCanvas: makeImageFromCanvas,
  makeVideo: makeVideo,
  error: error,
  runExtensionSupportedTest: runExtensionSupportedTest,
  shallowCopyObject: shallowCopyObject,
  setDefault3DContextVersion: setDefault3DContextVersion,
  setupColorQuad: setupColorQuad,
  setupProgram: setupProgram,
  setupTransformFeedbackProgram: setupTransformFeedbackProgram,
  setupQuad: setupQuad,
  setupQuadWithTexCoords: setupQuadWithTexCoords,
  setupIndexedQuad: setupIndexedQuad,
  setupIndexedQuadWithOptions: setupIndexedQuadWithOptions,
  setupSimpleColorProgram: setupSimpleColorProgram,
  setupSimpleTextureProgram: setupSimpleTextureProgram,
  setupSimpleTextureProgramESSL300: setupSimpleTextureProgramESSL300,
  setupSimpleCubeMapTextureProgram: setupSimpleCubeMapTextureProgram,
  setupSimpleVertexColorProgram: setupSimpleVertexColorProgram,
  setupNoTexCoordTextureProgram: setupNoTexCoordTextureProgram,
  setupTexturedQuad: setupTexturedQuad,
  setupTexturedQuadWithTexCoords: setupTexturedQuadWithTexCoords,
  setupTexturedQuadWithCubeMap: setupTexturedQuadWithCubeMap,
  setupUnitQuad: setupUnitQuad,
  setFloatDrawColor: setFloatDrawColor,
  setUByteDrawColor: setUByteDrawColor,
  startPlayingAndWaitForVideo: startPlayingAndWaitForVideo,
  startsWith: startsWith,
  shouldGenerateGLError: shouldGenerateGLError,
  shouldThrow: shouldThrow,
  readFile: readFile,
  readFileList: readFileList,
  replaceParams: replaceParams,
  requestAnimFrame: requestAnimFrame,
  runSteps: runSteps,
  waitForComposite: waitForComposite,

  // fullscreen api
  setupFullscreen: setupFullscreen,

  // color converter API
  namedColorInColorSpace: namedColorInColorSpace,
  colorAsSampledWithInternalFormat: colorAsSampledWithInternalFormat,

  // sRGB converter api
  sRGBToLinear: sRGBToLinear,
  linearToSRGB: linearToSRGB,

  getHost: getHost,
  getBaseDomain: getBaseDomain,
  runningOnLocalhost: runningOnLocalhost,
  getLocalCrossOrigin: getLocalCrossOrigin,
  getRelativePath: getRelativePath,
  awaitOrTimeout: awaitOrTimeout,
  awaitTimeout: awaitTimeout,

  none: false
};

Object.defineProperties(API, {
  noTexCoordTextureVertexShader: { value: noTexCoordTextureVertexShader, writable: false },
  simpleTextureVertexShader: { value: simpleTextureVertexShader, writable: false },
  simpleTextureVertexShaderESSL300: { value: simpleTextureVertexShaderESSL300, writable: false },
  simpleColorFragmentShader: { value: simpleColorFragmentShader, writable: false },
  simpleColorFragmentShaderESSL300: { value: simpleColorFragmentShaderESSL300, writable: false },
  simpleVertexShader: { value: simpleVertexShader, writable: false },
  simpleVertexShaderESSL300: { value: simpleVertexShaderESSL300, writable: false },
  simpleTextureFragmentShader: { value: simpleTextureFragmentShader, writable: false },
  simpleTextureFragmentShaderESSL300: { value: simpleTextureFragmentShaderESSL300, writable: false },
  simpleHighPrecisionTextureFragmentShader: { value: simpleHighPrecisionTextureFragmentShader, writable: false },
  simpleCubeMapTextureFragmentShader: { value: simpleCubeMapTextureFragmentShader, writable: false },
  simpleVertexColorFragmentShader: { value: simpleVertexColorFragmentShader, writable: false },
  simpleVertexColorVertexShader: { value: simpleVertexColorVertexShader, writable: false }
});

return API;

}());
