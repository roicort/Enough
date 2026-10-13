"""Convert capcheck/ai-image-detection from PyTorch to Core ML."""

import json
from pathlib import Path

import coremltools as ct
from PIL import Image
import torch
from transformers import AutoImageProcessor, AutoModelForImageClassification

model_id = "capcheck/ai-image-detection"
image_size = 224
repository_root = Path(__file__).resolve().parents[1]
output_path = repository_root / "Models" / "capcheck_ai_image_detection.mlpackage"
verification_path = (
    repository_root / "Models" / "capcheck_ai_image_detection.verification.json"
)

processor = AutoImageProcessor.from_pretrained(model_id)
if (
    processor.size["height"] != image_size
    or processor.size["width"] != image_size
    or tuple(processor.image_mean) != (0.5, 0.5, 0.5)
    or tuple(processor.image_std) != (0.5, 0.5, 0.5)
    or processor.rescale_factor != 1 / 255
):
    raise ValueError("The model preprocessing configuration changed unexpectedly.")

model = AutoModelForImageClassification.from_pretrained(model_id).eval()
if model.config.id2label != {0: "REAL", 1: "FAKE"}:
    raise ValueError(f"Unexpected labels: {model.config.id2label}")

# Convert the two-class classifier into the FAKE-minus-REAL logit used by Enough!.
fake_logit_classifier = torch.nn.Linear(model.classifier.in_features, 1)
with torch.no_grad():
    fake_logit_classifier.weight.copy_(
        model.classifier.weight[1:2] - model.classifier.weight[0:1]
    )
    fake_logit_classifier.bias.copy_(
        model.classifier.bias[1:2] - model.classifier.bias[0:1]
    )
model.classifier = fake_logit_classifier

original_forward = model.forward
model.forward = lambda pixel_values: original_forward(
    pixel_values=pixel_values
).logits

example_input = torch.rand(1, 3, image_size, image_size)
with torch.inference_mode():
    traced_model = torch.jit.trace(model, example_input)

coreml_model = ct.convert(
    traced_model,
    convert_to="mlprogram",
    inputs=[
        ct.ImageType(
            name="input",
            shape=example_input.shape,
            color_layout=ct.colorlayout.RGB,
            scale=2 / 255,
            bias=[-1, -1, -1],
        )
    ],
    outputs=[ct.TensorType(name="logit")],
    compute_precision=ct.precision.FLOAT32,
    minimum_deployment_target=ct.target.iOS16,
)

output_path.parent.mkdir(parents=True, exist_ok=True)
coreml_model.save(output_path)

pixels = torch.randint(
    low=0,
    high=256,
    size=(image_size, image_size, 3),
    dtype=torch.uint8,
).numpy()
image = Image.fromarray(pixels, mode="RGB")
with torch.inference_mode():
    torch_logit = model(
        processor(images=image, return_tensors="pt").pixel_values
    ).item()
coreml_logit = float(coreml_model.predict({"input": image})["logit"][0][0])
absolute_difference = abs(torch_logit - coreml_logit)
if absolute_difference > 1e-4:
    raise RuntimeError(
        f"Core ML verification failed: absolute logit difference is "
        f"{absolute_difference:.6f}."
    )

verification_path.write_text(
    json.dumps(
        {
            "torchLogit": torch_logit,
            "coremlLogit": coreml_logit,
            "absoluteDifference": absolute_difference,
        },
        indent=2,
    )
    + "\n"
)
print(f"Saved Core ML package to {output_path}")
print(f"Saved verification result to {verification_path}")
