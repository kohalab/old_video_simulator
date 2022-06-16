//NTSCでのYIQの帯域幅は
//Yは4.2MHz(つまり制限しない)
//Iは1.3MHz(1.4MHz?)
//Qは0.4MHz(0.5MHz?)
//全ての帯域幅は4.2MHz
//NTSCのガンマ値はブラウン管が2.2なので、先に1/2.2(約0.45)に補正する

//IQの変調はカラーバーストを0度として、Iは57度、Qは147度(57 + 90)となる

/*
メモ
 フィールドは奇数、偶数の順番で出される
 奇数フィールドの垂直同期は(1から数えて)9ライン目が伸びない
 偶数フィールドの垂直同期は(1から数えて)9ライン目が伸びてカラーバーストがない
 */

/*
 入力画像のドットを合わせたければ756x525pxにする
 
 756 = floor(dot_clock_frequency / (ntsc_horizontal_view_end - ntsc_horizontal_view_start))
 
 640x480の動画を正しく変換するなら、704(720 - 16)x480に引き伸ばして変換した後に640x480に戻す
 */

/*
バグとか
 
 */

enum video_mode {
  VIDEO_COMPOSITE, 
    VIDEO_SVIDEO, 
    VIDEO_YUV, 
    VIDEO_RGB,
}


video_mode video_mode_setting = video_mode.VIDEO_COMPOSITE;

enum deinterlace_mode {
  DEINTERLACE_NO, 
    DEINTERLACE_WEAVE,
}

deinterlace_mode deinterlace_mode_setting = deinterlace_mode.DEINTERLACE_WEAVE;

boolean use_analog_filter = false;//デコードに普通のフィルタを使う

boolean encoder_enable_ytrap = false;
boolean encoder_no_color_band_limit = true;
boolean encoder_no_chroma_band_limit = false;

boolean test_line = false;

boolean monochrome_composite_input = false;
boolean monochrome = false;

boolean reading_composite = false;
boolean raw_writing = false;//遅いよ


double hue = 0;//ラジアン
double saturation = 1; 
double brightness = 0;
double contrast = 0;

double restore_dc_speed = 100;//400 正しい映像なら100

void setup() {
  /*
  println((int)(1 / (ntsc_horizontal_view_end - ntsc_horizontal_view_start)));
   int start = 0;
   int len = 11570;
   String path = "/Users/user/Movies/NOMELON NOLEMON rem swimming jpg/";
   for (int i = start; i < start + len - 4; i += 4) {
   println("renban " + (i / 2) + " / " + ((start + len - 4) / 2));
   PImage inimg_A1 = loadImage(path + nf(i + 1 + 0, 5)+".jpg");
   PImage inimg_A2 = loadImage(path + nf(i + 1 + 1, 5)+".jpg");
   PImage inimg_B1 = loadImage(path + nf(i + 1 + 2, 5)+".jpg");
   PImage inimg_B2 = loadImage(path + nf(i + 1 + 3, 5)+".jpg");
   inimg_A1.resize(720 - 16, 480);
   inimg_A2.resize(720 - 16, 480);
   inimg_B1.resize(720 - 16, 480);
   inimg_B2.resize(720 - 16, 480);
   //println((525 / 2) - (inimg_A1.height / 2));
   PImage in_A1 = createImage(756, 525, RGB);
   in_A1.set((756 / 2) - (inimg_A1.width / 2), 40, inimg_A1);
   PImage in_A2 = createImage(756, 525, RGB);
   in_A2.set((756 / 2) - (inimg_A2.width / 2), 40, inimg_A2);
   PImage in_B1 = createImage(756, 525, RGB);
   in_B1.set((756 / 2) - (inimg_B1.width / 2), 40, inimg_B1);
   PImage in_B2 = createImage(756, 525, RGB);
   in_B2.set((756 / 2) - (inimg_B2.width / 2), 40, inimg_B2);
   
   PImage out = convert_ntsc_image(new PImage[] {in_A1, in_A2, in_B1, in_B2});
   //mysave("out/"+nf(i + 1, 5)+"debug.png", out);
   //横の位置は調整が必要
   mysave("out/"+nf((i / 2) + 1, 5)+".png", out.get(149, 34, 704, 480));
   mysave("out/"+nf((i / 2) + 2, 5)+".png", out.get(149, 34 + 525, 704, 480));
   }
   println("done");
   */

  double[] out;//出力用バッファ

  int start_millis = millis();

  println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"loading image");
  PImage input_image = loadImage("in.png");
  PImage input_composite = loadImage("in composite.png");
  if (input_composite == null || monochrome_composite_input == false) {
    input_composite = createImage(input_image.width, input_image.height, ARGB);
  }
  if (monochrome_composite_input == true) {
    input_image = createImage(input_composite.width, input_composite.height, ARGB);
  }
  println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"generate");
  signal[] video = generate(
    new PImage[] {input_image, input_image, input_image, input_image}, 
    new PImage[] {input_composite, input_composite, input_composite, input_composite}, 
    4);

  signal[] ntsc = null;
  if (!reading_composite) {
    if (video_mode_setting == video_mode.VIDEO_COMPOSITE || video_mode_setting == video_mode.VIDEO_SVIDEO) {
      println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"encode_rgb_to_ntsc");
      ntsc = encode_rgb_to_ntsc(video);

      double[] filter_in = new double[ntsc.length * 2];
      for (int i = 0; i < ntsc.length; i++) {
        filter_in[i] = ntsc[i].composite;
        filter_in[i + ntsc.length] = ntsc[i].composite;
      }
      //ハイパスフィルタ
      filter_in = high_pass_filter(filter_in, dot_clock_frequency, 10, 1 / Math.sqrt(2));
      if (false) {
        //エフェクト
        //過剰なDCカット
        filter_in = high_pass_filter(filter_in, dot_clock_frequency, 70, 0.5 / Math.sqrt(2));

        //ローパス
        filter_in = low_pass_filter(filter_in, dot_clock_frequency, 2 * 1000 * 1000, 0.2 / Math.sqrt(2));
        //色復元
        filter_in = add(filter_in, 
          band_pass_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 0.5), 
          1, 8);

        //水平シャープ
        filter_in = add(filter_in, 
          band_pass_filter(filter_in, dot_clock_frequency, 2.5 * 1000 * 1000, 1), 
          1, 1);

        filter_in = add(filter_in, 
          high_pass_filter(filter_in, dot_clock_frequency, 0.5 * 1000 * 1000, 0.5 / Math.sqrt(2)), 
          1, 0.1);
      }
      for (int i = 0; i < ntsc.length; i++) {
        ntsc[i].composite = filter_in[i + ntsc.length];
      }
    } else if (video_mode_setting == video_mode.VIDEO_YUV) {
      video = encode_rgb_to_yuv(video);
    }

    if (raw_writing) {
      println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"composite out");
      out = new double[ntsc.length];
      //出力
      for (int i = 0; i < out.length; i++) {
        out[i] = ntsc[i].composite;
      }
      out = restore_dc(out, restore_dc_speed);
      println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"composite write");
      double_float64_write(sketchPath("composite.raw"), out);
    }
  } else {
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"loading composite");
    double[] in = double_float64_read(sketchPath("composite in.raw"));
    ntsc = new signal[in.length];
    for (int i = 0; i < ntsc.length; i++) {
      ntsc[i] = new signal();
      ntsc[i].composite = in[i];
    }
  }

  //デコード
  signal[] YC = null;
  if (video_mode_setting == video_mode.VIDEO_COMPOSITE) {
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"YC_separation");
    YC = YC_separation(ntsc);//YC分離
  } else {
    YC = ntsc;
  }
  if (raw_writing) {
    if (video_mode_setting == video_mode.VIDEO_COMPOSITE || video_mode_setting == video_mode.VIDEO_SVIDEO) {
      out = new double[ntsc.length];
      println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"Y out");
      for (int i = 0; i < out.length; i++) {
        out[i] = ntsc[i].Y;
      }
      out = restore_dc(out, restore_dc_speed);
      //out = restore_dc(sync_in, restore_dc_speed);
      println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"Y write");
      double_float64_write(sketchPath("Y.raw"), out);

      println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"C out");
      for (int i = 0; i < out.length; i++) {
        out[i] = ntsc[i].C;
      }
      println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"C write");
      double_float64_write(sketchPath("C.raw"), out);
    }
  }
  if (video_mode_setting == video_mode.VIDEO_COMPOSITE) {
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"decode");
    signal[] decode = decode_ntsc(YC);
    signal[] rgb = yiq_to_rgb(decode);
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"rgb_to_image");
    rgb_to_image(rgb, deinterlace_mode_setting).save("dec COMPOSITE.png");
  } else if (video_mode_setting == video_mode.VIDEO_SVIDEO) {
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"decode");
    signal[] decode = decode_ntsc(YC);//SVIDEOだけどsync_separationのためにcomposite信号が必須
    signal[] rgb = yiq_to_rgb(decode);
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"rgb_to_image");
    rgb_to_image(rgb, deinterlace_mode_setting).save("dec SVIDEO.png");
  } else if (video_mode_setting == video_mode.VIDEO_YUV) {
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"decode");
    signal[] yuv = encode_rgb_to_yuv(video);
    signal[] rgb = yiq_to_rgb(yuv);
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"rgb_to_image");
    rgb_to_image(rgb, deinterlace_mode_setting).save("dec YUV.png");
  } else if (video_mode_setting == video_mode.VIDEO_RGB) {
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"decode");
    signal[] rgb = video;
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"rgb_to_image");
    rgb_to_image(rgb, deinterlace_mode_setting).save("dec RGB.png");
  } else {
    println("video_mode_settingが何かしらおかしい");
  }


  println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"done");
  //*/
  exit();
  return;//ダメ押し
}

PImage convert_ntsc_image(PImage[] in) {
  signal[] video = generate(in, null, 4);

  signal[] ntsc = encode_rgb_to_ntsc(video);

  double[] filter_in = new double[ntsc.length];
  for (int i = 0; i < ntsc.length; i++) {
    filter_in[i] = ntsc[i].composite;
  }
  //ハイパスフィルタ
  filter_in = high_pass_filter(filter_in, dot_clock_frequency, 1, 1 / Math.sqrt(2));

  //エフェクト
  /*
  //過激なローパス
   filter_in = low_pass_filter(filter_in, dot_clock_frequency, 4 * 1000 * 1000, 1 / Math.sqrt(2));
   filter_in = add(
   filter_in, low_pass_filter(filter_in, dot_clock_frequency, 1 * 1000 * 1000, 1 / Math.sqrt(2)), 0.6, 0.4);
   
   //過剰なDCカット
   filter_in = high_pass_filter(filter_in, dot_clock_frequency, 300, 2 / Math.sqrt(2));
   
   //水平シャープ
   filter_in = add(filter_in, 
   band_pass_filter(filter_in, dot_clock_frequency, 5 * 1000 * 1000, 0.5), 
   1, 2);
   
   filter_in = add(filter_in, 
   high_pass_filter(filter_in, dot_clock_frequency, 1 * 1000 * 1000, 0.5 / Math.sqrt(2)), 
   1, 0.1);
   */

  for (int i = 0; i < ntsc.length; i++) {
    ntsc[i].composite = filter_in[i];
  }

  signal[] YC = null;
  YC = YC_separation(ntsc);//YC分離

  signal[] decode = decode_ntsc(YC);
  signal[] rgb = yiq_to_rgb(decode);
  return rgb_to_image(rgb, deinterlace_mode_setting);
}
