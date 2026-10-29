"""Run the local prototype: python -m service [--port 8000]."""
import argparse
import uvicorn


def main():
    parser = argparse.ArgumentParser(description="运行开饭 HTML 原型和调度 API")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    uvicorn.run("service.app:app", host=args.host, port=args.port)


if __name__ == "__main__":
    main()
