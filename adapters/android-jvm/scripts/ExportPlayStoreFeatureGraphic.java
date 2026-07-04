// [Android-JVMアダプタ] Play Store フィーチャーグラフィック（1024x500 PNG）生成ユーティリティ
import java.awt.Color;
import java.awt.GradientPaint;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.Path2D;
import java.awt.geom.RoundRectangle2D;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

public final class ExportPlayStoreFeatureGraphic {
    private static final int WIDTH = 1024;
    private static final int HEIGHT = 500;

    public static void main(String[] args) throws Exception {
        String output = args.length > 0 ? args[0] : "play-store/feature-graphic-1024x500.png";
        BufferedImage image = new BufferedImage(WIDTH, HEIGHT, BufferedImage.TYPE_INT_RGB);
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
        g.setPaint(new GradientPaint(0, 0, color("#2E403B"), WIDTH, HEIGHT, color("#263A35")));
        g.fillRect(0, 0, WIDTH, HEIGHT);

        g.setColor(alpha("#17212B", 0.28f));
        roundRect(g, 585, 80, 230, 300, 32);

        g.setColor(color("#6D6550"));
        roundRect(g, 610, 58, 220, 285, 30);

        g.setColor(color("#354A44"));
        roundRect(g, 540, 88, 300, 320, 34);

        g.setColor(color("#5C7169"));
        Path2D side = new Path2D.Double();
        side.moveTo(574, 88);
        side.lineTo(610, 88);
        side.lineTo(610, 408);
        side.lineTo(574, 408);
        side.curveTo(554, 408, 540, 394, 540, 374);
        side.lineTo(540, 122);
        side.curveTo(540, 102, 554, 88, 574, 88);
        side.closePath();
        g.fill(side);

        g.setColor(color("#D7E4DC"));
        Path2D chevron = new Path2D.Double();
        chevron.moveTo(655, 178);
        chevron.lineTo(752, 248);
        chevron.lineTo(655, 318);
        chevron.lineTo(655, 282);
        chevron.lineTo(704, 248);
        chevron.lineTo(655, 214);
        chevron.closePath();
        g.fill(chevron);

        g.setColor(alpha("#D7E4DC", 0.13f));
        roundRect(g, 150, 132, 280, 20, 10);
        roundRect(g, 150, 182, 350, 18, 9);
        roundRect(g, 150, 230, 250, 18, 9);
        roundRect(g, 150, 278, 320, 18, 9);
        roundRect(g, 150, 326, 220, 18, 9);
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
