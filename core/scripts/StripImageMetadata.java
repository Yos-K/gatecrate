// [汎用コア] 画像メタデータ除去・リサイズ（Play Store用スクリーンショット準備） — スタック非依存
// Usage: java StripImageMetadata <input> <output>
// Default target: 1080x1920 (Play Store portrait). Override via env: TARGET_WIDTH, TARGET_HEIGHT
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

public final class StripImageMetadata {
    private static final int DEFAULT_TARGET_WIDTH = 1080;
    private static final int DEFAULT_TARGET_HEIGHT = 1920;

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("Usage: StripImageMetadata <input> <output>");
            System.exit(1);
        }

        int targetWidth = parseEnvInt("TARGET_WIDTH", DEFAULT_TARGET_WIDTH);
        int targetHeight = parseEnvInt("TARGET_HEIGHT", DEFAULT_TARGET_HEIGHT);

        BufferedImage input = ImageIO.read(new File(args[0]));
        if (input == null) {
            throw new IllegalArgumentException("Unsupported image: " + args[0]);
        }

        double scale = Math.max((double) targetWidth / input.getWidth(), (double) targetHeight / input.getHeight());
        int scaledWidth = (int) Math.ceil(input.getWidth() * scale);
        int scaledHeight = (int) Math.ceil(input.getHeight() * scale);
        int x = (targetWidth - scaledWidth) / 2;
        int y = 0;

        BufferedImage output = new BufferedImage(targetWidth, targetHeight, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = output.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
        g.drawImage(input, x, y, scaledWidth, scaledHeight, null);
        g.dispose();

        File out = new File(args[1]);
        File parent = out.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }
        ImageIO.write(output, "jpg", out);
    }

    private static int parseEnvInt(String name, int defaultValue) {
        String val = System.getenv(name);
        if (val == null || val.isEmpty()) return defaultValue;
        try {
            return Integer.parseInt(val);
        } catch (NumberFormatException e) {
            return defaultValue;
        }
    }
}
