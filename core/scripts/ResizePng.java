// [汎用コア] PNG画像リサイズユーティリティ — スタック非依存
// Usage: java ResizePng <input.png> <size> <output.png>
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

public final class ResizePng {
    private ResizePng() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            throw new IllegalArgumentException("Usage: ResizePng <input.png> <size> <output.png>");
        }
        File input = new File(args[0]);
        int size = Integer.parseInt(args[1]);
        File output = new File(args[2]);
        BufferedImage source = ImageIO.read(input);
        if (source == null) {
            throw new IllegalArgumentException("Input is not a readable image: " + input);
        }
        BufferedImage resized = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        java.awt.Graphics2D graphics = resized.createGraphics();
        try {
            graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
            graphics.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
            graphics.drawImage(source, 0, 0, size, size, null);
        } finally {
            graphics.dispose();
        }
        File parent = output.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }
        ImageIO.write(resized, "png", output);
    }
}
