double[] restore_dc(double[] in, double speed) {
  //最低レベルを0レベルとしてDCを再生
  double[] out = new double[in.length];

  //鋭いパルスを無視するための入力LPF
  double in_lowpass_filter_cutoff = (400 * 1000);
  double[] in_lpf = rc_low_pass_filter(in, dot_clock_frequency, in_lowpass_filter_cutoff);

  double min = 100;//最低の値
  for (int i = 0; i < in.length; i++) {
    if (in_lpf[i] < min) {
      min = in_lpf[i];
    }

    //最低レベルをゆっくり上げる
    //ハイパスがキツくなければspeed400くらい ダメなら3000とか
    min /= 1 + (speed / dot_clock_frequency);
    //min += (1 / dot_clock_frequency);

    out[i] = in[i] + ntsc_sync_level - min;
  }
  return out;
}


signal[] sync_separation(signal[] in) {
  //出力の同期信号は立ち上がりエッジで同期
  //垂直同期は複合同期でラッチされる(0.5ライン遅れる)
  double[] sync_in = new double[in.length];
  for (int i = 0; i < in.length; i++) {
    sync_in[i] = in[i].composite;
  }
  sync_in = restore_dc(sync_in, restore_dc_speed);
  double[] lowpass = rc_low_pass_filter(sync_in, dot_clock_frequency, 400 * 1000);

  signal[] out = new signal[in.length];

  boolean c_sync = false;

  boolean h_sync = false;
  double h_sync_longer = 0;

  double v_sync_timer = 0;
  double v_sync_longer = 0;

  boolean h_sync_old = false;
  double h_sync_timer = 0;
  int h_sync_counter = 0;

  boolean v_sync_latch = false;
  boolean v_sync_latch_old = false;
  boolean v_sync_old = false;

  boolean v_field = false;//false=odd true=even

  double h_counter = 0;
  for (int i = 0; i < in.length; i++) {
    out[i] = new signal();
    if (lowpass[i] > (ntsc_sync_level / 2) + (ntsc_sync_level / 6)) {
      c_sync = false;
    }
    if (lowpass[i] <= (ntsc_sync_level / 2) - (ntsc_sync_level / 6)) {
      c_sync = true;//正理論
    }

    if (c_sync) {
      h_sync_longer = 1;
    } else {
      h_sync_longer -= (1 / ntsc_horizontal_sync_pulse_end) / dot_clock_frequency * 10;
    }

    h_sync = h_sync_longer > 0;

    if (c_sync) {
      v_sync_timer += (1 / ntsc_horizontal_serrated_sync_pulse_end) / dot_clock_frequency * 1.2;
    } else {
      v_sync_timer = 0;
    }

    boolean v_sync = v_sync_timer >= 1;

    if (v_sync) {
      v_sync_longer = 1;
    } else {
      v_sync_longer -= (1 / ntsc_horizontal_sync_pulse_end) / dot_clock_frequency / 4;
    }

    v_sync = v_sync_longer > 0;

    //h_sync posedge, HALF-H Killer
    if (h_sync_old == false && h_sync == true) {
      //h_syncの立ち上がりエッジ
      if (h_sync_timer > 0.6) {
        //早すぎるh_syncでなければ
        h_sync_timer = 0;//タイマーリセット
      } else {
        //早すぎるh_sync
      }

      v_sync_latch = v_sync;//v_sync latch
      h_sync_counter++;

      if (v_sync_latch && !v_sync_latch_old) {
        //println(h_sync_counter);
        //垂直同期までに水平同期の立ち上がりカウントが
        if (h_sync_counter <= 271) {
          //271以下なら奇数フィールド
          v_field = false;
        } else {
          //272より上なら偶数フィールド
          v_field = true;
        }
        //println(h_sync_counter, v_field);
        h_sync_counter = 0;
      }
      v_sync_latch_old = v_sync_latch;
      //println("e");
    } else {
      h_sync_timer += (1 / ntsc_horizontal_end) / dot_clock_frequency;
      //println();
    }
    h_sync_old = h_sync;

    v_sync = v_sync_latch;

    h_sync = (h_sync_timer == 0);

    if (h_sync) {
      h_counter = 0;
    } else {
      h_counter += (1 / ntsc_horizontal_end) / dot_clock_frequency;
    }

    final double us = (double)1 / 1000 / 1000;
    boolean burst = 
      (h_counter >= ((5.3 + 0.5) * us) / ntsc_horizontal_end) && 
      (h_counter <= ((7.8 - 0.9) * us) / ntsc_horizontal_end);

    //v_sync oneshot
    boolean temp = v_sync_old == false && v_sync == true;
    v_sync_old = v_sync;
    v_sync = temp;

    out[i].H_sync = h_sync;
    out[i].V_sync = v_sync;
    out[i].composite_sync = c_sync;
    out[i].burst = burst;
    out[i].field = v_field;

    //out[i].Y = c_sync ? 1:0;//debug
    //out[i].Y = lowpass[i];
    //out[i].Y = h_sync ? 1 : 0;
  }
  return out;
}

signal[] YC_separation(signal[] in, YCSeparationMethods yc_separation_methods) {
  double[] filter_in = new double[in.length];
  for (int i = 0; i < in.length; i++) {
    filter_in[i] = in[i].composite;
  }
  filter_in = restore_dc(filter_in, restore_dc_speed);

  double[] Y = new double[in.length];
  double[] C = new double[in.length];
  if (monochrome) {
    for (int i = 0; i < filter_in.length; i++) {
      Y[i] = filter_in[i] * (ntsc_luminance_level - ntsc_color_burst_level / 2);
    }
  } else if (yc_separation_methods == YCSeparationMethods.FIR) {
    double[] chroma_notch = {
    /*
フィルタ長 : N = 15
     フィルタの種類 : BEF
     窓の種類 : Kaiser窓
     正規化低域遮断周波数 : 0.15
     正規化高域遮断周波数 : 0.35
     阻止域減衰量 : 48 [dB]
     */
      -2.573598731820087e-18, 
      -1.123023032498687e-02, 
      0.000000000000000e+00, 
      -4.810157979725212e-02, 
      2.902073588951772e-17, 
      2.588294279174700e-01, 
      0.000000000000000e+00, 
      6.000000000000001e-01, 
      0.000000000000000e+00, 
      2.588294279174700e-01, 
      2.902073588951772e-17, 
      -4.810157979725212e-02, 
      0.000000000000000e+00, 
      -1.123023032498687e-02, 
      -2.573598731820087e-18, 
    };
    double[] chroma_bandpass = {
    /*
フィルタ長 : N = 63
     フィルタの種類 : BPF
     窓の種類 : Blackman窓
     正規化低域遮断周波数 : 0.125714 (1.8 MHz)
     正規化高域遮断周波数 : 0.307302 (4.4 MHz)
     */
      -6.232528527560829e-20, 
      1.941268407374687e-05, 
      1.096998398783070e-05, 
      -4.736176800061733e-05, 
      6.267413486262296e-05, 
      -3.253505564059201e-04, 
      -8.064105721086482e-04, 
      4.186342493537989e-04, 
      1.033131177744515e-03, 
      -3.574304214961296e-06, 
      1.931682699327314e-03, 
      2.121526565623681e-03, 
      -4.643139988941855e-03, 
      -4.740927406338984e-03, 
      1.143402567837041e-03, 
      -3.578132404227390e-03, 
      1.770563375808178e-04, 
      1.854289949277739e-02, 
      8.325319595207265e-03, 
      -1.230439911675197e-02, 
      2.002578151864195e-04, 
      -1.149299544888987e-02, 
      -4.320252285608461e-02, 
      6.730142403091879e-03, 
      5.526528953553259e-02, 
      7.666068668637842e-03, 
      2.836804401514413e-02, 
      7.507358801613138e-02, 
      -1.193866621933264e-01, 
      -2.596868519444637e-01, 
      7.151243810590056e-02, 
      3.631760000000000e-01, 
      7.151243810590056e-02, 
      -2.596868519444637e-01, 
      -1.193866621933264e-01, 
      7.507358801613138e-02, 
      2.836804401514413e-02, 
      7.666068668637842e-03, 
      5.526528953553259e-02, 
      6.730142403091879e-03, 
      -4.320252285608461e-02, 
      -1.149299544888987e-02, 
      2.002578151864195e-04, 
      -1.230439911675197e-02, 
      8.325319595207265e-03, 
      1.854289949277739e-02, 
      1.770563375808178e-04, 
      -3.578132404227390e-03, 
      1.143402567837041e-03, 
      -4.740927406338984e-03, 
      -4.643139988941855e-03, 
      2.121526565623681e-03, 
      1.931682699327314e-03, 
      -3.574304214961296e-06, 
      1.033131177744515e-03, 
      4.186342493537989e-04, 
      -8.064105721086482e-04, 
      -3.253505564059201e-04, 
      6.267413486262296e-05, 
      -4.736176800061733e-05, 
      1.096998398783070e-05, 
      1.941268407374687e-05, 
      -6.232528527560829e-20, 
    };

    /*
    double[] LPF = fir_filter(filter_in, chroma_notch);
     double[] HPF = new double[LPF.length];
     for (int i = 0; i < LPF.length; i++) {
     HPF[i] = filter_in[i] - LPF[i];
     }
     double[] delay_1h = fir_filter(
     HPF, 
     new double[] {1, 0, 0}, 
     (int)(dot_clock_frequency / ntsc_horizontal_frequency)
     );//1H遅延された信号
     
     for (int i = 0; i < filter_in.length; i++) {
     Y[i] = (filter_in[i] + delay_1h[i]);
     C[i] = (filter_in[i] - delay_1h[i]) / 2;
     }
     */

    double[] delay_1h = fir_filter(
      filter_in, 
      new double[] {1, 0, 0}, 
      (int)(dot_clock_frequency / ntsc_horizontal_frequency)
      );//1H遅延された信号

    double[] future_1h = fir_filter(
      filter_in, 
      new double[] {0, 0, 1}, 
      (int)(dot_clock_frequency / ntsc_horizontal_frequency)
      );//1H進んだ信号

    //適応型YC分離
    for (int i = 4; i < filter_in.length - 4; i++) {

      double fade = 0;

      for (int f = -2; f < 2; f++) {
        fade += Math.abs(filter_in[i - 2 + f] - filter_in[i + 2 + f]) - Math.abs(filter_in[i + f] - delay_1h[i + f]);
      }
      fade /= 4;
      //垂直方向の差が多ければ水平フィルタを、水平方向の差が多ければ垂直フィルタを使う
      fade *= 8;
      if (fade < -1)fade = -1;
      if (fade > +1)fade = +1;
      fade += 1;
      fade /= 2;

      //水平フィルタ
      double hori_Y = (filter_in[i - 2] + (2 * filter_in[i]) + filter_in[i + 2]) / 4;
      double hori_C = -(filter_in[i - 2] - (2 * filter_in[i]) + filter_in[i + 2]) / 4;

      //垂直フィルタ
      double vert_Y = (future_1h[i] + (2 * filter_in[i]) + delay_1h[i]) / 4;
      double vert_C = -(future_1h[i] - (2 * filter_in[i]) + delay_1h[i]) / 4;

      Y[i] = lerp(hori_Y, vert_Y, fade);
      C[i] = lerp(hori_C, vert_C, fade);
    }

    Y = fir_filter(Y, new double[] {-0.05, -0.1, 1.3, -0.1, -0.05}); //シャープ

    //Y = fir_filter(Y, chroma_notch);
  } else if (yc_separation_methods == YCSeparationMethods.BPF_NOTCH) {
    double[] BPF = null;
    BPF = band_pass_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 0.6);
    C = BPF;
    Y = notch_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 2.5);
  } else if (yc_separation_methods == YCSeparationMethods.RC_FILTER) {
    Y = rc_low_pass_filter(filter_in, dot_clock_frequency, 1 * 1000 * 1000);
    C = rc_high_pass_filter(filter_in, dot_clock_frequency, 1 * 1000 * 1000);
  }
  /*
   //1ライン遅延したのと計算して二次元Y/C分離
   double[] FIR = fir_filter(
   BPF, 
   new double[] {-0.5, 0.5}, 
   (int)(dot_clock_frequency / ntsc_horizontal_frequency)
   );
   
   Y = add(filter_in, FIR, 1, -1);
   C = FIR;
   */
  signal[] out = new signal[in.length];

  for (int i = 0; i < in.length; i++) {
    out[i] = in[i];
    out[i].Y = Y[i];
    out[i].C = C[i];
  }
  return out;
}

signal[] decode_ntsc(signal[] in) {
  //inはYC分離済み
  signal[] sync = sync_separation(in);
  /*
  boolean[] test = new boolean[sync.length];
   for (int i = 0; i < sync.length; i++) {
   test[i] = sync[i].H_sync;
   }
   double_boolean_write(sketchPath("H_sync.raw"), test);
   for (int i = 0; i < sync.length; i++) {
   test[i] = sync[i].V_sync;
   }
   double_boolean_write(sketchPath("V_sync.raw"), test);
   for (int i = 0; i < sync.length; i++) {
   test[i] = sync[i].burst;
   }
   double_boolean_write(sketchPath("burst.raw"), test);
   */
  double[] Y = new double[in.length];
  double[] I = new double[in.length];
  double[] Q = new double[in.length];

  for (int i = 0; i < in.length; i++) {
    double Yi = in[i].Y;
    //double Ii = in[i].C * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) + ((double)(57 - 45) / 360 * Math.PI * 2) + hue);
    //double Qi = in[i].C * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) + ((double)(147 - 45) / 360 * Math.PI * 2) + hue);
    double Ii = in[i].C * Math.cos((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) + hue);
    double Qi = in[i].C * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) + hue);
    //double Ii = -in[i].C * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2));
    //double Qi = in[i].C * Math.cos((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2));

    //Yi = (Yi * (ntsc_luminance_level + ntsc_sync_level)) - (ntsc_sync_level * 2);//テスト用コントラスト低減
    /*
    Ii *= Math.sqrt(2) * 2 * saturation;
     Qi *= Math.sqrt(2) * 2 * saturation;
     */
    if (monochrome) {
      //Yi = in[i].Y + in[i].C;
      Ii = 0;
      Qi = 0;
    }

    Y[i] = Yi;
    I[i] = Ii;
    Q[i] = Qi;
  }

  double[] Y_emphasis_coefficient = {
  /*
  フィルタ長 : N = 7
   フィルタの種類 : HPF
   窓の種類 : Kaiser窓
   正規化遮断周波数 : 0.45
   阻止域減衰量 : 37 [dB]
   */
    -1.712647514742823e-02, 
    5.129307467785612e-02, 
    -8.553262415712180e-02, 
    9.999999999999998e-02, 
    -8.553262415712180e-02, 
    5.129307467785612e-02, 
    -1.712647514742823e-02, 
  };
  double[] Y_emphasis = fir_filter(Y, Y_emphasis_coefficient);
  for (int i = 0; i < Y.length; i++) {
    Y_emphasis[i] *= 40;
    double e = (Y_emphasis[i] * Y_emphasis[i]);
    if (e < -ntsc_luminance_level / 3)e = -ntsc_luminance_level / 3;
    if (e > +ntsc_luminance_level / 3)e = +ntsc_luminance_level / 3;
    Y[i] += e;
  }

  /*
  double[] Y_emphasis = new double[Y.length];
   double Y_emphasis_cutoff = dot_clock_frequency / (10 * 1000 * 1000);
   for (int i = 1; i < Y.length; i++) {
   Y_emphasis[i] = (Y[i] + (Y_emphasis[i - 1] * Y_emphasis_cutoff)) / (Y_emphasis_cutoff + 1);
   }
   for (int i = 0; i < Y.length; i++) {
   Y[i] += ((Y[i] - Y_emphasis[i]) * 1);
   }
   */
  //Y = notch_filter(Y, dot_clock_frequency, ntsc_color_subcarrier_frequency, 2);//模様低減
  //Y = low_pass_filter(Y, dot_clock_frequency, 4.2 * 1000 * 1000, 2);//シャープ

  //Y = low_pass_filter(Y, dot_clock_frequency, ntsc_color_subcarrier_frequency / 2, 1 / Math.sqrt(2));//ただの遅延
  //I = low_pass_filter(I, dot_clock_frequency, ntsc_color_subcarrier_frequency / 2, 1 / Math.sqrt(2));//復調
  //Q = low_pass_filter(Q, dot_clock_frequency, ntsc_color_subcarrier_frequency / 2, 1 / Math.sqrt(2));//復調

  double[] I_lowpass_coefficient = {
  /*
    フィルタ長 : N = 31
   フィルタの種類 : LPF
   窓の種類 : Blackman窓
   正規化遮断周波数 : 0.05
   */
    //2.944958038392145e-19, -8.670717849467505e-05, -3.319550967880867e-04, -6.269783635101152e-04, -6.891897353101802e-04, 5.067623382275192e-19, 2.194265176660287e-03, 6.770228567408323e-03, 1.449504765874971e-02, 2.572136877875045e-02, 4.010704565915763e-02, 5.647463951586574e-02, 7.289735515160392e-02, 8.702886530667454e-02, 9.660811335016214e-02, 9.999999999999999e-02, 9.660811335016214e-02, 8.702886530667454e-02, 7.289735515160392e-02, 5.647463951586574e-02, 4.010704565915763e-02, 2.572136877875045e-02, 1.449504765874971e-02, 6.770228567408323e-03, 2.194265176660287e-03, 5.067623382275192e-19, -6.891897353101802e-04, -6.269783635101152e-04, -3.319550967880867e-04, -8.670717849467505e-05, 2.944958038392145e-19, 
  /*
フィルタ長 : N = 31
   フィルタの種類 : LPF
   窓の種類 : Kaiser窓
   正規化遮断周波数 : 0.08
   阻止域減衰量 : 96 [dB]
   */
    1.026988961089344e-05, 5.621385400920854e-05, 7.059891453952769e-05, -1.834287635486377e-04, -1.112256280642084e-03, -3.042067070784576e-03, -5.692405787177795e-03, -7.589730817401900e-03, -5.866802475165842e-03, 3.115075776282794e-03, 2.224967793477264e-02, 5.179761074492555e-02, 8.810882846584892e-02, 1.238884446624489e-01, 1.502719502235165e-01, 1.600000000000000e-01, 1.502719502235165e-01, 1.238884446624489e-01, 8.810882846584892e-02, 5.179761074492555e-02, 2.224967793477264e-02, 3.115075776282794e-03, -5.866802475165842e-03, -7.589730817401900e-03, -5.692405787177795e-03, -3.042067070784576e-03, -1.112256280642084e-03, -1.834287635486377e-04, 7.059891453952769e-05, 5.621385400920854e-05, 1.026988961089344e-05, 
  };

  if (use_analog_filter) {
    I = low_pass_filter(I, dot_clock_frequency, 0.7 * 1000 * 1000, 1);
  } else {
    I = fir_filter(I, I_lowpass_coefficient);
    //I = fir_filter(I, new double[] {0.25, 0.25, 0.25, 0.25});
  }

  double[] Q_lowpass_coefficient = {
  /*
    フィルタ長 : N = 31
   フィルタの種類 : LPF
   窓の種類 : Blackman窓
   正規化遮断周波数 : 0.05
   */
    //2.944958038392145e-19, -8.670717849467505e-05, -3.319550967880867e-04, -6.269783635101152e-04, -6.891897353101802e-04, 5.067623382275192e-19, 2.194265176660287e-03, 6.770228567408323e-03, 1.449504765874971e-02, 2.572136877875045e-02, 4.010704565915763e-02, 5.647463951586574e-02, 7.289735515160392e-02, 8.702886530667454e-02, 9.660811335016214e-02, 9.999999999999999e-02, 9.660811335016214e-02, 8.702886530667454e-02, 7.289735515160392e-02, 5.647463951586574e-02, 4.010704565915763e-02, 2.572136877875045e-02, 1.449504765874971e-02, 6.770228567408323e-03, 2.194265176660287e-03, 5.067623382275192e-19, -6.891897353101802e-04, -6.269783635101152e-04, -3.319550967880867e-04, -8.670717849467505e-05, 2.944958038392145e-19, 
  /*
フィルタ長 : N = 31
   フィルタの種類 : LPF
   窓の種類 : Kaiser窓
   正規化遮断周波数 : 0.08
   阻止域減衰量 : 96 [dB]
   */
    1.026988961089344e-05, 5.621385400920854e-05, 7.059891453952769e-05, -1.834287635486377e-04, -1.112256280642084e-03, -3.042067070784576e-03, -5.692405787177795e-03, -7.589730817401900e-03, -5.866802475165842e-03, 3.115075776282794e-03, 2.224967793477264e-02, 5.179761074492555e-02, 8.810882846584892e-02, 1.238884446624489e-01, 1.502719502235165e-01, 1.600000000000000e-01, 1.502719502235165e-01, 1.238884446624489e-01, 8.810882846584892e-02, 5.179761074492555e-02, 2.224967793477264e-02, 3.115075776282794e-03, -5.866802475165842e-03, -7.589730817401900e-03, -5.692405787177795e-03, -3.042067070784576e-03, -1.112256280642084e-03, -1.834287635486377e-04, 7.059891453952769e-05, 5.621385400920854e-05, 1.026988961089344e-05, 
  };

  if (use_analog_filter) {
    Q = low_pass_filter(Q, dot_clock_frequency, 0.7 * 1000 * 1000, 1);
  } else {
    Q = fir_filter(Q, Q_lowpass_coefficient);
    //Q = fir_filter(Q, new double[] {0.25, 0.25, 0.25, 0.25});
  }
  //I = notch_filter(I, dot_clock_frequency, ntsc_color_subcarrier_frequency, 2);//模様低減
  //Q = notch_filter(Q, dot_clock_frequency, ntsc_color_subcarrier_frequency, 2);//模様低減
  /*
  //輝度シャープ
   double[] Y_sharpen = high_pass_filter(Y, dot_clock_frequency, 4.2 * 1000 * 1000, 1 / Math.sqrt(2));
   Y_sharpen = notch_filter(Y_sharpen, dot_clock_frequency, ntsc_color_subcarrier_frequency, 1);
   Y = add(Y, Y_sharpen, 1, -5);
   
   //色シャープ
   I = add(I, high_pass_filter(I, dot_clock_frequency, ntsc_color_subcarrier_frequency / 1.5, 1 / Math.sqrt(2)), 1, -10);
   Q = add(Q, high_pass_filter(Q, dot_clock_frequency, ntsc_color_subcarrier_frequency / 1.5, 1 / Math.sqrt(2)), 1, -10);
   */

  double burst_I = 0;
  double burst_Q = 0;
  double burst_hue = 0;
  double chroma_level = 1;

  double[] smooth_Y_coefficient = {
  /*
    フィルタ長 : N = 15
   フィルタの種類 : LPF
   窓の種類 : Kaiser
   正規化遮断周波数 : 0.139684 (1MHz)
   阻止域減衰量 : 48 [dB]
   */
    1.805457184828473e-03, 
    -1.034474699361243e-03, 
    -1.319121232652857e-02, 
    -2.684845052545213e-02, 
    -1.742391073052172e-02, 
    3.930387752297802e-02, 
    1.388378936103093e-01, 
    2.377260734749734e-01, 
    2.793680000000000e-01, 
    2.377260734749734e-01, 
    1.388378936103093e-01, 
    3.930387752297802e-02, 
    -1.742391073052172e-02, 
    -2.684845052545213e-02, 
    -1.319121232652857e-02, 
    -1.034474699361243e-03, 
    1.805457184828473e-03, 
  };
  double[] smooth_Y = fir_filter(Y, smooth_Y_coefficient);

  double black_level_cutoff = rc_filter_hz_to_a(dot_clock_frequency, (100 * 1000));
  double burst_smooth_cutoff = rc_filter_hz_to_a(dot_clock_frequency, (100 * 1000));

  double black_level = 0;

  signal[] out = new signal[in.length];
  for (int i = 0; i < in.length; i++) {

    if (sync[i].burst && !sync[i].V_sync) {
      //基準色相
      /*
      burst_I = (I[i] + burst_I * burst_smooth_cutoff) / (burst_smooth_cutoff + 1);
       burst_Q = (Q[i] + burst_Q * burst_smooth_cutoff) / (burst_smooth_cutoff + 1);
       */
      burst_I += (I[i] - burst_I) * burst_smooth_cutoff;
      burst_Q += (Q[i] - burst_Q) * burst_smooth_cutoff;

      chroma_level = Math.sqrt((burst_I * burst_I) + (burst_Q * burst_Q));

      //基準黒レベル
      black_level += (smooth_Y[i] - black_level) * black_level_cutoff;

      if (chroma_level > ntsc_color_burst_level / 8) {
        //burst_hue = Math.atan2(-burst_I, -burst_Q) + ((double)33 / 360 * TWO_PI);
        burst_hue = Math.atan2(burst_I, burst_Q) + ((double)180 / 360 * TWO_PI);
        //burst_hue = (double)i / 10000;
        /*
      if (i % 10 == 0) {
         println("I:"+burst_I+" "+"Q:"+burst_Q+" "+"burst_hue:"+burst_hue);
         }
         */
      } else {
        chroma_level = 1;
      }
    }
    double rotation_hue = 0;
    //rotation_hue = ((double)(147 - 45) / 360 * Math.PI * 2);;
    //rotation_hue = (double)i / 100000;
    rotation_hue += burst_hue;
    rotation_hue += hue;
    double Ii = I[i];//バックアップ重要
    double Qi = Q[i];
    I[i] = (Ii * Math.cos(rotation_hue)) - (Qi * Math.sin(rotation_hue));
    Q[i] = (Ii * Math.sin(rotation_hue)) + (Qi * Math.cos(rotation_hue));

    Y[i] -= black_level;
    //Y[i] *= -ntsc_sync_level + 1;

    if (i == 100000) {
      //println(black_level);
    }


    Y[i] += brightness;
    Y[i] *= contrast + 1;

    I[i] /= 1 / saturation * chroma_level * 1.414 * 4;
    Q[i] /= 1 / saturation * chroma_level * 1.414 * 4;

    //out[i] = in[i];//その他の情報は保持
    out[i] = new signal();
    out[i].Y = Y[i];
    out[i].I = I[i];
    out[i].Q = Q[i];

    out[i].H_sync = sync[i].H_sync;
    out[i].V_sync = sync[i].V_sync;
    out[i].composite_sync = sync[i].composite_sync;
    out[i].field = sync[i].field;
  }
  return out;
}

signal[] yiq_to_rgb(signal[] in) {
  signal[] out = new signal[in.length];
  for (int i = 0; i < in.length; i++) {
    out[i] = new signal();
    double Y = in[i].Y / ntsc_luminance_level;
    double I = in[i].I;
    double Q = in[i].Q;

    double[] RGB = YIQ_to_RGB(new double[] {Y, I, Q});
    /*
    RGB[0] = gamma(RGB[0], 1 / 2.2);
     RGB[1] = gamma(RGB[1], 1 / 2.2);
     RGB[2] = gamma(RGB[2], 1 / 2.2);
     */
    out[i].R = RGB[0];
    out[i].G = RGB[1];
    out[i].B = RGB[2];

    out[i].H_sync = in[i].H_sync;
    out[i].V_sync = in[i].V_sync;
    out[i].composite_sync = in[i].composite_sync;
    out[i].field = in[i].field;
  }
  return out;
}

PImage rgb_to_image(signal[] in, DeinterlaceMode mode) {
  PImage out;
  int width = (int)Math.round(ntsc_horizontal_end * dot_clock_frequency);
  out = createImage(width, in.length / width, ARGB);
  for (int y = 0; y < out.height; y++) {
    for (int x = 0; x < out.width; x++) {
      //出力画像は黒で塗りつぶしておく
      out.set(x, y, #000000);
    }
  }


  boolean h_sync_prev = false;
  boolean v_sync_prev = false;

  int x = 0;
  int y = 0;

  int frame = -1;//最初に垂直同期があるから
  boolean field = false;
  int field_count = 0;

  for (int i = 0; i < in.length; i++) {
    /*
    int x = i % width;
     int y = i / width;
     
     int field = (int)Math.floor((double)y / ntsc_vertical_field_number_of_line);
     int frame = (int)Math.floor((double)y / ntsc_vertical_frame_number_of_line);
     
     if (mode == DeinterlaceMode.DEINTERLACE_WEAVE) {
     //単純なインターレース解除
     //奇数、偶数の順番に送られてくる
     y = (int)Math.floor((y - ((double)field * ntsc_vertical_field_number_of_line)) * 2);
     y += Math.floor((frame * ntsc_vertical_frame_number_of_line));
     }
     */

    x += 1;
    if ((h_sync_prev == false && in[i].H_sync) || x > 950) {
      //水平同期の立ち上がりでyに2を足す
      //println("hsync");
      y++;
      x = 0;
    }

    if ((v_sync_prev == false && in[i].V_sync) || y > 263) {
      println(y);
      x = 0;
      y = 0;
      //println(in[i].field);
      if (!in[i].field || field_count >= 2) {
        //奇数フィールドで垂直同期になったらフレームを次に
        frame++;
        field_count = 0;
        //println(frame);
      }
      field = in[i].field;
      //println(y);
      println(field, field_count, frame);//デバッグ用
      field_count++;
    }

    h_sync_prev = in[i].H_sync;
    v_sync_prev = in[i].V_sync;

    color c = color(0, 255, 0);

    //in[i].R = in[i].G = in[i].B = 0.5;
    double R = in[i].R;
    double G = in[i].G;
    double B = in[i].B;
    if (gamma) {
      R = sRGB_gamma(R);
      G = sRGB_gamma(G);
      B = sRGB_gamma(B);
    }

    c = color((float)(R * 255), (float)(G * 255), (float)(B * 255));
    out.set(x, 
      (y * 2) + (frame * (int)ntsc_vertical_frame_number_of_line) + (field ? 1 : 0)
      , c);
  }
  return out;
}
