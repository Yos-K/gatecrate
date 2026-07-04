// [Android-JVMアダプタ] Play Store アイコン（512x512 PNG）生成ユーティリティ
import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.Path2D;
import java.awt.geom.RoundRectangle2D;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

public final class ExportPlayStoreIcon {
    private static final int SIZE = 512;
    private static final double SCALE = SIZE / 108.0;

    public static void main(String[] args) throws Exception {
        String output = args.length > 0 ? args[0] : "play-store/icon-512.png";
        BufferedImage image = new BufferedImage(SIZE, SIZE, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = image.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);

        draw(g);
        g.dispose();

        File out = new File(output);
        File parent = out.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }
        ImageIO.write(image, "png", out);
    }

    private static void draw(Graphics2D g) {
        g.setColor(color("#2E403B"));
        g.fillRect(0, 0, SIZE, SIZE);

        g.scale(SCALE, SCALE);

        g.setColor(alpha("#17212B", 0.22f));
        roundRect(g, 35, 24, 40, 69, 7);

        g.setColor(color("#6D6550"));
        roundRect(g, 40, 20, 40, 57, 5);

        g.setColor(color("#354A44"));
        roundRect(g, 20, 25, 64, 66, 7);

        g.setColor(color("#5C7169"));
        Path2D side = new Path2D.Double();
        side.moveTo(27, 25);
        side.lineTo(34, 25);
        side.lineTo(34, 91);
        side.lineTo(27, 91);
        side.curveTo(23, 91, 20, 88, 20, 84);
        side.lineTo(20, 32);
        side.curveTo(20, 28, 23, 25, 27, 25);
        side.closePath();
        g.fill(side);

        g.setColor(color("#D7E4DC"));
        Path2D chevron = new Path2D.Double();
        chevron.moveTo(46, 44);
        chevron.lineTo(64, 57);
        chevron.lineTo(46, 70);
        chevron.lineTo(46, 63);
        chevron.lineTo(55, 57);
        chevron.lineTo(46, 51);
        chevron.closePath();
        g.fill(chevron);

        g.setStroke(new BasicStroke(0.8f));
    }

    private static void roundRect(Graphics2D g, double x, double y, double width, double height, double radius) {
        g.fill(new RoundRectangle2D.Double(x, y, width, height, radius * 2, radius * 2));
    }

    private static Color color(String hex) {
        return new Color(Integer.parseInt(hex.substring(1), 16));
    }

    private static Color alpha(String hex, float alpha) {
        Color base = color(hex);
        return new Color(base.getRed(), base.getGreen(), base.getBlue(), Math.round(alpha * 255));
    }
}
