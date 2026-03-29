import io

try:
    import qrcode
    from qrcode.image.svg import SvgPathImage
except ModuleNotFoundError:
    qrcode = None
    SvgPathImage = None


def build_qr_svg(payload: str, box_size: int = 6, border: int = 2) -> str:
    if not payload or qrcode is None or SvgPathImage is None:
        return ""

    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=box_size,
        border=border,
    )
    qr.add_data(payload)
    qr.make(fit=True)

    buffer = io.BytesIO()
    image = qr.make_image(image_factory=SvgPathImage)
    image.save(buffer)
    return buffer.getvalue().decode("utf-8")
