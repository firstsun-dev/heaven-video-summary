#!/usr/bin/env python3
"""Transcribe audio file using mlx-whisper."""

import sys
from pathlib import Path

import mlx_whisper


def transcribe_audio(audio_file: str, output_txt: str, model: str) -> bool:
    """
    Transcribe audio file and save transcript.

    Args:
        audio_file: Path to audio file
        output_txt: Path to output transcript file
        model: Model name or Hugging Face repo ID

    Returns:
        True if successful, False otherwise
    """
    try:
        audio_path = Path(audio_file).resolve()
        output_path = Path(output_txt).resolve()

        if not audio_path.exists():
            print(f"❌ Audio file not found: {audio_path}", file=sys.stderr)
            return False

        # Ensure output directory exists
        output_path.parent.mkdir(parents=True, exist_ok=True)

        # Transcribe
        result = mlx_whisper.transcribe(
            str(audio_path),
            path_or_hf_repo=model,
            language='zh',
            initial_prompt='請用繁體中文回答',
            verbose=True
        )

        # Write transcript
        with open(output_path, 'w', encoding='utf-8') as f:
            for segment in result['segments']:
                f.write(segment['text'].strip() + '\n')

        print('Transcription complete', file=sys.stderr)
        return True

    except Exception as e:
        print(f"❌ Transcription error: {e}", file=sys.stderr)
        return False


if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: transcribe_audio.py <audio_file> <output_txt> <model>", file=sys.stderr)
        sys.exit(1)

    audio_file, output_txt, model = sys.argv[1:]
    success = transcribe_audio(audio_file, output_txt, model)
    sys.exit(0 if success else 1)
