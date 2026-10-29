import argparse
from pathlib import Path
from . import Request, generate_plan

parser = argparse.ArgumentParser(description="Generate a cooking plan from JSON")
parser.add_argument("input", type=Path)
args = parser.parse_args()
print(generate_plan(Request.model_validate_json(args.input.read_text())).model_dump_json(indent=2))
