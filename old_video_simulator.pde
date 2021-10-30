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

boolean test_line = false;

boolean monochrome_composite_input = false;
boolean monochrome = false;

boolean reading_composite = false;
boolean raw_writing = false;//遅いよ

void setup() {
  /*
  int start = 0;
   int len = 6268;
   for (int i = start; i < start + len; i += 2) {
   println("renban " + i + " / " + len);
   PImage inimg_A = loadImage("/Users/user/Movies/【Ado】踊 SD jpegs/"+nf(i + 1, 3)+".jpg");
   PImage inimg_B = loadImage("/Users/user/Movies/【Ado】踊 SD jpegs/"+nf(i + 1 + 1, 3)+".jpg");
   PImage in_A = createImage(756, 525, RGB);
   in_A.set((756 / 2) - (640 / 2), 42, inimg_A);
   
   PImage in_B = createImage(756, 525, RGB);
   in_B.set((756 / 2) - (640 / 2), 42, inimg_B);
   PImage out = convert_ntsc_image(new PImage[] {in_A, in_A, in_B, in_B});
   mysave("out/"+nf(i + 0, 5)+".jpg", out.get(191, 42, 640, 480));
   mysave("out/"+nf(i + 1, 5)+".jpg", out.get(191, 42 + 525, 640, 480));
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

      double[] filter_in = new double[ntsc.length];
      for (int i = 0; i < ntsc.length; i++) {
        filter_in[i] = ntsc[i].composite;
      }
      //ハイパスフィルタ
      filter_in = high_pass_filter(filter_in, dot_clock_frequency, 1, 1 / Math.sqrt(2));

      for (int i = 0; i < ntsc.length; i++) {
        ntsc[i].composite = filter_in[i];
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
      println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"composite write");
      double_float64_write(sketchPath("composite.raw"), out);
    }
  } else {
    println("["+String.format("%5d", millis() - start_millis)+"ms]" + " " +"loading composite");
    double[] in = double_float64_read(sketchPath("composite in.raw"));
    //in = restore_dc(in);
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
  filter_in = high_pass_filter(filter_in, dot_clock_frequency, 20, 1 / Math.sqrt(2));

  for (int i = 0; i < ntsc.length; i++) {
    ntsc[i].composite = filter_in[i];
  }

  signal[] YC = null;
  YC = YC_separation(ntsc);//YC分離

  signal[] decode = decode_ntsc(YC);
  signal[] rgb = yiq_to_rgb(decode);
  return rgb_to_image(rgb, deinterlace_mode_setting);
}
