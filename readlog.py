#!/usr/bin/env python3
import sys
from pathlib import Path

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} /path/to/file", file=sys.stderr)
        sys.exit(1)

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"Error: File does not exist: {path}", file=sys.stderr)
        sys.exit(1)

    # Read file content
    try:
        data = path.read_text(errors="replace")
    except UnicodeDecodeError:
        print("Error: Failed to decode file as text.", file=sys.stderr)
        sys.exit(1)

    # Print the exact content Python read (control characters escaped)
    # repr() renders non-printable chars like \x1b and \n
    print(repr(data))

if __name__ == "__main__":
    main()