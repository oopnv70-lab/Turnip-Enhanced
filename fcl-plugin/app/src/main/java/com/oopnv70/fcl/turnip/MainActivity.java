package com.oopnv70.fcl.turnip;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

/**
 * FCL 驱动插件本身没有界面逻辑。
 *
 * FCL 识别插件的唯一依据是 AndroidManifest 里的 metaData（fclPlugin / driver /
 * driver_lib / driver_gpu），与这个 Activity 无关。这个入口只用于让插件在系统里
 * 显示为一个可点开的应用，点开后展示实际加载的库信息，方便排查。
 */
public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        TextView tv = new TextView(this);
        tv.setPadding(64, 96, 64, 64);
        tv.setTextSize(16f);
        tv.setText(buildInfo());
        setContentView(tv);
    }

    private String buildInfo() {
        StringBuilder sb = new StringBuilder();
        sb.append("Turnip Enhanced — FCL 驱动插件\n\n");
        sb.append("本插件不提供独立界面，作用是让 FCL 启动器\n");
        sb.append("在「版本设置 → 驱动」里多出一个可选驱动。\n\n");
        sb.append("用法：\n");
        sb.append("1. 安装本 APK\n");
        sb.append("2. 打开 FCL → 某个整合包 → 版本设置\n");
        sb.append("3. 驱动一栏选择 Turnip Enhanced\n");
        sb.append("4. 渲染器选 Zink 或 Freedreno\n\n");
        sb.append("库名：libvulkan_freedreno.so\n");
        sb.append("GPU 家族：adreno\n");
        sb.append("nativeLibraryDir：\n");
        sb.append(getApplicationInfo().nativeLibraryDir).append("\n");
        return sb.toString();
    }
}
