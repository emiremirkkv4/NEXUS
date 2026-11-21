package local.nexusmission.monitor;

import android.content.Context;
import android.graphics.*;
import android.view.View;
import java.util.List;

final class Trend extends View {
    private final List<double[]> history;
    private final Paint pen = new Paint(Paint.ANTI_ALIAS_FLAG);
    Trend(Context context, List<double[]> history) {
        super(context);
        this.history = history;
        setContentDescription("Processor and memory usage for the last minute, zero to one hundred percent.");
    }
    @Override protected void onDraw(Canvas c) {
        float w = getWidth(), h = getHeight(), top = 8, bottom = h - 12;
        pen.setColor(0xff304054);
        pen.setStrokeWidth(1);
        for (int i = 0; i <= 4; i++) {
            float y = top + (bottom - top) * i / 4;
            c.drawLine(0, y, w, y, pen);
        }
        if (history.isEmpty()) return;
        double latest = history.get(history.size()-1)[0];
        for (int field = 1; field <= 2; field++) {
            pen.setColor(field == 1 ? 0xff6ee9fc : 0xff8e9bff);
            pen.setStrokeWidth(4);
            float lastX = 0, lastY = 0;
            boolean first = true;
            for (double[] p : history) {
                float x = (float)(w - 3 - (latest - p[0]) / 60 * (w - 6));
                float y = (float)(bottom - p[field] / 100 * (bottom-top));
                if (!first) c.drawLine(lastX,lastY,x,y,pen);
                c.drawCircle(x,y,2,pen);
                first = false; lastX = x; lastY = y;
            }
        }
    }
}
