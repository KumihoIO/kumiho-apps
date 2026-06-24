"""
PNG and image metadata extraction for Kumiho Ingest.

Extracts:
- Image dimensions (width, height)
- Color type information
- PNG text chunks (tEXt, iTXt) which may contain ComfyUI workflow data
- ComfyUI generation settings (prompt, model, LoRAs, seed, etc.)
"""

import json
import os
import struct
import zlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


# PNG signature bytes
PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'

# PNG color type names
PNG_COLOR_TYPES = {
    0: 'grayscale',
    2: 'rgb',
    3: 'indexed',
    4: 'grayscale_alpha',
    6: 'rgba',
}


def extract_png_metadata(file_path: str) -> Dict[str, Any]:
    """
    Extract metadata from a PNG file.

    Returns a dict with:
    - width: image width in pixels
    - height: image height in pixels
    - color_type: color type name (rgb, rgba, grayscale, etc.)
    - bit_depth: bits per channel
    - file_size: file size in bytes
    - text_chunks: dict of PNG text chunks (may contain ComfyUI workflow)
    - generation_settings: extracted ComfyUI generation settings (if found)

    All values are converted to strings for Kumiho metadata storage compatibility.
    """
    result = {}

    if not file_path or not os.path.isfile(file_path):
        return result

    try:
        result['file_size'] = str(os.path.getsize(file_path))
    except Exception:
        pass

    try:
        with open(file_path, 'rb') as f:
            # Verify PNG signature
            signature = f.read(8)
            if signature != PNG_SIGNATURE:
                return result

            text_chunks = {}

            # Read chunks
            while True:
                chunk_header = f.read(8)
                if len(chunk_header) < 8:
                    break

                length = struct.unpack('>I', chunk_header[:4])[0]
                chunk_type = chunk_header[4:8].decode('ascii', errors='ignore')

                # Read chunk data
                chunk_data = f.read(length)

                # Skip CRC
                f.read(4)

                if chunk_type == 'IHDR':
                    # Image header - extract dimensions and color info
                    if len(chunk_data) >= 13:
                        width, height = struct.unpack('>II', chunk_data[:8])
                        bit_depth = chunk_data[8]
                        color_type = chunk_data[9]

                        result['width'] = str(width)
                        result['height'] = str(height)
                        result['bit_depth'] = str(bit_depth)
                        result['color_type'] = PNG_COLOR_TYPES.get(color_type, str(color_type))

                elif chunk_type == 'tEXt':
                    # Uncompressed text chunk
                    try:
                        null_idx = chunk_data.index(b'\x00')
                        key = chunk_data[:null_idx].decode('latin-1')
                        value = chunk_data[null_idx + 1:].decode('latin-1')
                        text_chunks[key] = value
                    except Exception:
                        pass

                elif chunk_type == 'iTXt':
                    # International text chunk (UTF-8)
                    try:
                        null_idx = chunk_data.index(b'\x00')
                        key = chunk_data[:null_idx].decode('utf-8')
                        # Skip compression flag, compression method, language tag, translated keyword
                        rest = chunk_data[null_idx + 1:]
                        compression_flag = rest[0]
                        # Skip to the text content (after language and translated keyword null terminators)
                        rest = rest[2:]  # Skip compression flag and method
                        # Find end of language tag
                        null_idx = rest.index(b'\x00')
                        rest = rest[null_idx + 1:]
                        # Find end of translated keyword
                        null_idx = rest.index(b'\x00')
                        text_data = rest[null_idx + 1:]

                        if compression_flag:
                            text_data = zlib.decompress(text_data)

                        value = text_data.decode('utf-8')
                        text_chunks[key] = value
                    except Exception:
                        pass

                elif chunk_type == 'zTXt':
                    # Compressed text chunk
                    try:
                        null_idx = chunk_data.index(b'\x00')
                        key = chunk_data[:null_idx].decode('latin-1')
                        # Skip compression method byte
                        compressed_data = chunk_data[null_idx + 2:]
                        value = zlib.decompress(compressed_data).decode('latin-1')
                        text_chunks[key] = value
                    except Exception:
                        pass

                elif chunk_type == 'IEND':
                    break

            if text_chunks:
                result['text_chunks'] = text_chunks

                # Try to extract ComfyUI workflow and generation settings
                generation_settings = extract_comfyui_settings(text_chunks)
                if generation_settings:
                    result['generation_settings'] = generation_settings

    except Exception:
        pass

    return result


def extract_comfyui_settings(text_chunks: Dict[str, str]) -> Dict[str, str]:
    """
    Extract ComfyUI generation settings from PNG text chunks.

    ComfyUI embeds workflow data in 'workflow' and 'prompt' text chunks.
    This function parses them to extract:
    - prompt: positive prompt text
    - negative_prompt: negative prompt text
    - model: checkpoint/model name
    - loras: comma-separated LoRA names with strengths
    - seed: seed value
    - steps: number of steps
    - cfg: CFG scale
    - sampler: sampler name
    - scheduler: scheduler name
    - width, height: image dimensions (from workflow)
    """
    settings = {}

    # Try to parse 'prompt' chunk (API format) first, then 'workflow' chunk
    workflow_data = None

    for key in ['prompt', 'workflow']:
        if key in text_chunks:
            try:
                workflow_data = json.loads(text_chunks[key])
                break
            except Exception:
                continue

    if not workflow_data:
        return settings

    # Parse the workflow
    parser = WorkflowParser(workflow_data)
    parser.parse()

    return parser.extract_generation_settings()


class WorkflowParser:
    """
    Parse ComfyUI workflow JSON to extract generation settings.

    Ported from kumiho-comfyui's WorkflowParser with modifications for
    standalone use without ComfyUI dependencies.
    """

    def __init__(self, workflow: Dict[str, Any]):
        self.workflow = workflow
        self.nodes: Dict[str, Dict[str, Any]] = {}

    def parse(self) -> None:
        """Parse all nodes in the workflow."""
        # Handle both prompt format and workflow format
        if 'nodes' in self.workflow:
            # Full workflow format (from workflow chunk)
            for node in self.workflow.get('nodes', []):
                node_id = str(node.get('id'))
                self.nodes[node_id] = {
                    'type': node.get('type'),
                    'widgets_values': node.get('widgets_values', []),
                    'inputs': node.get('inputs', {}),
                }
        else:
            # Prompt format (from API / prompt chunk)
            for node_id, node_data in self.workflow.items():
                if isinstance(node_data, dict) and 'class_type' in node_data:
                    self.nodes[node_id] = {
                        'type': node_data.get('class_type'),
                        'inputs': node_data.get('inputs', {}),
                    }

    def extract_generation_settings(self) -> Dict[str, str]:
        """
        Extract generation settings from workflow nodes.

        Returns a dict with string values suitable for Kumiho metadata storage.
        """
        settings: Dict[str, str] = {}

        # Node types that contain sampler settings
        sampler_node_types = {
            'KSampler': {'steps': 'steps', 'cfg': 'cfg', 'sampler': 'sampler_name', 'scheduler': 'scheduler', 'seed': 'seed'},
            'KSamplerAdvanced': {'steps': 'steps', 'cfg': 'cfg', 'sampler': 'sampler_name', 'scheduler': 'scheduler', 'seed': 'noise_seed'},
            'SamplerCustom': {'steps': 'steps', 'cfg': 'cfg', 'seed': 'noise_seed'},
            'SamplerCustomAdvanced': {'seed': 'noise_seed'},
        }

        # Collect found values
        prompts_found: List[str] = []
        negative_prompts_found: List[str] = []
        models_found: List[str] = []
        loras_found: List[str] = []
        width: Optional[int] = None
        height: Optional[int] = None

        for node_id, node_info in self.nodes.items():
            node_type = node_info.get('type', '')
            inputs = node_info.get('inputs', {})
            widgets = node_info.get('widgets_values', [])

            # Extract sampler settings (steps, cfg, sampler, scheduler, seed)
            if node_type in sampler_node_types:
                param_map = sampler_node_types[node_type]
                for setting_key, input_key in param_map.items():
                    if isinstance(inputs, dict) and input_key in inputs:
                        val = inputs[input_key]
                        # Skip if it's a connection reference (list like [node_id, output_index])
                        if val is not None and not isinstance(val, list):
                            if setting_key not in settings:  # Keep first found
                                settings[setting_key] = str(val)

            # Extract prompts from CLIPTextEncode
            if node_type == 'CLIPTextEncode':
                text = None
                if isinstance(inputs, dict) and 'text' in inputs:
                    text = inputs.get('text')
                elif widgets:
                    text = widgets[0] if widgets else None

                if text and isinstance(text, str):
                    # Determine if positive or negative based on common patterns
                    text_lower = text.lower()
                    negative_keywords = [
                        'ugly', 'bad', 'worst', 'blurry', 'nsfw', 'watermark',
                        'deformed', 'disfigured', 'mutated', 'lowres', 'low quality',
                        'error', 'cropped', 'jpeg artifacts', 'signature', 'username'
                    ]
                    is_negative = any(neg in text_lower for neg in negative_keywords)
                    if is_negative:
                        negative_prompts_found.append(text)
                    else:
                        prompts_found.append(text)

            # Extract model name from checkpoint loaders
            if node_type in ['CheckpointLoaderSimple', 'CheckpointLoader', 'UNETLoader']:
                ckpt_name = None
                if isinstance(inputs, dict):
                    ckpt_name = inputs.get('ckpt_name') or inputs.get('unet_name')
                elif widgets:
                    ckpt_name = widgets[0] if widgets else None

                if ckpt_name and isinstance(ckpt_name, str):
                    # Clean up the name (remove path, extension)
                    model_name = Path(ckpt_name).stem
                    models_found.append(model_name)

            # Extract LoRA names
            if node_type in ['LoraLoader', 'LoraLoaderModelOnly']:
                lora_name = None
                if isinstance(inputs, dict):
                    lora_name = inputs.get('lora_name')
                elif widgets:
                    lora_name = widgets[0] if widgets else None

                if lora_name and isinstance(lora_name, str):
                    lora_clean = Path(lora_name).stem
                    # Extract strength if available
                    strength = None
                    if isinstance(inputs, dict):
                        strength = inputs.get('strength_model') or inputs.get('strength')
                    elif len(widgets) > 1:
                        strength = widgets[1] if isinstance(widgets[1], (int, float)) else None

                    if strength is not None:
                        loras_found.append(f"{lora_clean}:{strength}")
                    else:
                        loras_found.append(lora_clean)

            # Extract dimensions from EmptyLatentImage
            if node_type in ['EmptyLatentImage', 'EmptySD3LatentImage']:
                if isinstance(inputs, dict):
                    if 'width' in inputs and not isinstance(inputs['width'], list):
                        width = inputs['width']
                    if 'height' in inputs and not isinstance(inputs['height'], list):
                        height = inputs['height']
                elif widgets and len(widgets) >= 2:
                    width = widgets[0] if isinstance(widgets[0], int) else None
                    height = widgets[1] if isinstance(widgets[1], int) else None

        # Compile results
        if prompts_found:
            settings['prompt'] = prompts_found[0]
        if negative_prompts_found:
            settings['negative_prompt'] = negative_prompts_found[0]
        if models_found:
            settings['model'] = models_found[0]
        if loras_found:
            settings['loras'] = ','.join(loras_found)
        if width and height:
            settings['width'] = str(width)
            settings['height'] = str(height)

        return settings


def extract_image_dimensions(file_path: str) -> Optional[Tuple[int, int]]:
    """
    Fast extraction of image dimensions only.

    Returns (width, height) tuple or None if extraction fails.
    Supports PNG format.
    """
    if not file_path or not os.path.isfile(file_path):
        return None

    try:
        with open(file_path, 'rb') as f:
            # Check for PNG
            signature = f.read(8)
            if signature == PNG_SIGNATURE:
                # Read IHDR chunk
                chunk_header = f.read(8)
                if len(chunk_header) >= 8:
                    chunk_type = chunk_header[4:8]
                    if chunk_type == b'IHDR':
                        ihdr_data = f.read(8)
                        if len(ihdr_data) >= 8:
                            width, height = struct.unpack('>II', ihdr_data[:8])
                            return (width, height)
    except Exception:
        pass

    return None


def get_metadata_for_revision(file_path: str) -> Dict[str, str]:
    """
    Get metadata suitable for Kumiho revision storage.

    Returns a flat dict with string values only, merging image properties
    and generation settings at the top level.
    """
    metadata = {}

    png_meta = extract_png_metadata(file_path)

    # Add basic image properties
    for key in ['width', 'height', 'color_type', 'bit_depth', 'file_size']:
        if key in png_meta:
            metadata[key] = png_meta[key]

    # Merge generation settings at top level
    if 'generation_settings' in png_meta:
        for key, value in png_meta['generation_settings'].items():
            # Don't overwrite image dimensions from actual file with workflow dimensions
            if key not in metadata:
                metadata[key] = value

    return metadata


def get_workflow_json(file_path: str) -> Optional[str]:
    """
    Extract the raw workflow JSON string from a PNG file.

    Returns the workflow or prompt JSON as a string, or None if not found.
    Useful for storing the complete workflow for reproducibility.
    """
    png_meta = extract_png_metadata(file_path)
    text_chunks = png_meta.get('text_chunks', {})

    # Return workflow or prompt chunk as-is
    for key in ['workflow', 'prompt']:
        if key in text_chunks:
            return text_chunks[key]

    return None
