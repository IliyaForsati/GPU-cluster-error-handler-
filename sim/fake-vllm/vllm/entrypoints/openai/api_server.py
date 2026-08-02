# KubeAI's Model controller hardcodes this exact module path as the
# launch command for engine: VLLM (see k8s/kubeai/fake-model.yaml) - it
# always runs "python3 -m vllm.entrypoints.openai.api_server ...", no
# matter what image you point it at. A fake image can only be managed by
# a real Model CR if something answers to that exact invocation, so this
# stub package exists purely so that command resolves - it just runs the
# same fake HTTP server as the plain Deployment (app.py), ignoring the
# real vLLM CLI args (--model, --served-model-name, ...) it gets called
# with, since there is no real model behind it anyway.
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from app import main

if __name__ == "__main__":
    main()
