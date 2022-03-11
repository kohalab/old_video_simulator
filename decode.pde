double[] restore_dc(double[] in, double speed) {
  //最低レベルを0レベルとしてDCを再生
  double[] out = new double[in.length];

  //鋭いパルスを無視するための入力LPF
  double in_lowpass_filter = 0;
  double in_lowpass_filter_cutoff = dot_clock_frequency / (3 * 1000 * 1000);

  double min = 0;//最低の値
  for (int i = 0; i < in.length; i++) {
    in_lowpass_filter = ((in[i]) + in_lowpass_filter * (in_lowpass_filter_cutoff - 1)) / in_lowpass_filter_cutoff;

    if (in_lowpass_filter < min) {
      min = in_lowpass_filter;
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
  sync_in = restore_dc(sync_in, 300);
  double[] lowpass = low_pass_filter(sync_in, dot_clock_frequency, 800 * 1000, 0.5 / Math.sqrt(2));

  signal[] out = new signal[in.length];

  boolean c_sync = false;

  boolean h_sync = false;
  double h_sync_longer = 0;

  double v_sync_timer = 0;
  double v_sync_longer = 0;

  boolean h_sync_old = false;
  double h_sync_timer = 0;

  boolean v_sync_latch = false;
  boolean v_sync_old = false;

  double h_counter = 0;
  for (int i = 0; i < in.length; i++) {
    out[i] = new signal();
    if (lowpass[i] > (ntsc_sync_level / 2) + 0.08) {
      c_sync = false;
    }
    if (lowpass[i] <= (ntsc_sync_level / 2) - 0.08) {
      c_sync = true;//正理論
    }

    if (c_sync) {
      h_sync_longer = 1;
    } else {
      h_sync_longer -= (1 / ntsc_horizontal_sync_pulse_end) / dot_clock_frequency * 10;
    }

    h_sync = h_sync_longer > 0;

    if (c_sync) {
      v_sync_timer += (1 / ntsc_horizontal_sync_pulse_end) / dot_clock_frequency / 2;
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

    //HALF-H Killer
    if (h_sync_old == false && h_sync == true) {
      //h_syncの立ち上がりエッジ
      if (h_sync_timer > 0.6) {
        //早すぎるh_syncでなければ
        h_sync_timer = 0;//タイマーリセット
      }
      v_sync_latch = v_sync;//v_sync latch
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

    //out[i].Y = c_sync ? 1:0;//debug
    //out[i].Y = lowpass[i];
    //out[i].Y = h_sync ? 1 : 0;
  }
  return out;
}

signal[] YC_separation(signal[] in) {
  double[] filter_in = new double[in.length];
  for (int i = 0; i < in.length; i++) {
    filter_in[i] = in[i].composite;
  }

  double[] Y = new double[in.length];
  double[] C = new double[in.length];

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

  double[] BPF = null;

  if (use_analog_filter) {
    BPF = band_pass_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 0.6);
    C = BPF;
    Y = notch_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 2.5);
  } else {
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
        fade = Math.abs(filter_in[i - 2 + f] - filter_in[i + 2 + f]) - Math.abs(filter_in[i + f] - delay_1h[i + f]);
      }
      fade /= 4;
      //垂直方向の差が多ければ水平フィルタを、水平方向の差が多ければ垂直フィルタを使う
      fade *= 4;
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

    //Y = fir_filter(Y, chroma_notch);
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


  if (use_analog_filter) {
  } else {
    /*
    Y = fir_filter(
     Y, 
     new double[] {
     //-0.1, 0.25, 0.35, 0.35, 0.25, -0.1
     0.2, 0.3, 0.3, 0.2
     } 
     //chroma_notch
     );
     */
  }

  signal[] out = new signal[in.length];

  for (int i = 0; i < in.length; i++) {
    out[i] = in[i];
    out[i].Y = Y[i];
    out[i].C = C[i];
  }
  return out;
}

double hue = 0;
double saturation = 1.3; 
double brightness = 0;
double contrast = 0;

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
    double Ii = in[i].C * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) + ((double)(57 - 45) / 360 * Math.PI * 2) + hue);
    double Qi = in[i].C * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) + ((double)(147 - 45) / 360 * Math.PI * 2) + hue);
    //double Ii = -in[i].C * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2));
    //double Qi = in[i].C * Math.cos((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2));

    //Yi = (Yi * (ntsc_luminance_level + ntsc_sync_level)) - (ntsc_sync_level * 2);//テスト用コントラスト低減
    /*
    Ii *= Math.sqrt(2) * 2 * saturation;
     Qi *= Math.sqrt(2) * 2 * saturation;
     */
    if (monochrome) {
      Ii = 0;
      Qi = 0;
    }

    Y[i] = Yi;
    I[i] = Ii;
    Q[i] = Qi;
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
    フィルタ長 : N = 63
   フィルタの種類 : LPF
   窓の種類 : Hamming
   正規化遮断周波数 : 0.104762 (1.5MHz)
   */
    //8.213531771889800e-04, 6.832272332554459e-04, 2.326992384764049e-04, -4.674366656991243e-04, -1.217533234472174e-03, -1.664262477516988e-03, -1.406866520163575e-03, -2.270778123493983e-04, 1.661994083589523e-03, 3.519965227262240e-03, 4.276831686422424e-03, 3.025186166374356e-03, -3.808928125686136e-04, -4.941283933724483e-03, -8.640719728480408e-03, -9.193749530606022e-03, -5.186555416366614e-03, 2.881836189320047e-03, 1.223972637496650e-02, 1.854302514038311e-02, 1.757145652253882e-02, 7.349556202273495e-03, -1.020976955280664e-02, -2.900466237907973e-02, -4.020521848737567e-02, -3.518404156097370e-02, -8.940072332086725e-03, 3.730847765995627e-02, 9.550662954773868e-02, 1.525852968087095e-01, 1.942584864661476e-01, 2.095240000000000e-01, 1.942584864661476e-01, 1.525852968087095e-01, 9.550662954773868e-02, 3.730847765995627e-02, -8.940072332086725e-03, -3.518404156097370e-02, -4.020521848737567e-02, -2.900466237907973e-02, -1.020976955280664e-02, 7.349556202273495e-03, 1.757145652253882e-02, 1.854302514038311e-02, 1.223972637496650e-02, 2.881836189320047e-03, -5.186555416366614e-03, -9.193749530606022e-03, -8.640719728480408e-03, -4.941283933724483e-03, -3.808928125686136e-04, 3.025186166374356e-03, 4.276831686422424e-03, 3.519965227262240e-03, 1.661994083589523e-03, -2.270778123493983e-04, -1.406866520163575e-03, -1.664262477516988e-03, -1.217533234472174e-03, -4.674366656991243e-04, 2.326992384764049e-04, 6.832272332554459e-04, 8.213531771889800e-04, 
  /*
フィルタ長 : N = 47
   フィルタの種類 : LPF
   窓の種類 : Blackman窓
   正規化遮断周波数 : 0.209524 (3MHz)
   */
    //1.742673394214716e-19, -1.553410708509952e-05, 6.142752443864771e-05, 2.370265491629509e-04, -5.918660218780589e-05, -8.485164630872996e-04, -5.202488037993005e-04, 1.669304111936031e-03, 2.386365413757806e-03, -1.761657712050434e-03, -5.915356487278223e-03, -7.291933574932576e-04, 1.021174072452739e-02, 8.039540142470502e-03, -1.222541607918958e-02, -2.149050883068006e-02, 6.443346248735778e-03, 4.005695840052305e-02, 1.546488981439756e-02, -5.984318432951385e-02, -7.156896878214679e-02, 7.516659953122014e-02, 3.057228372966000e-01, 4.190479999999999e-01, 3.057228372966000e-01, 7.516659953122014e-02, -7.156896878214679e-02, -5.984318432951385e-02, 1.546488981439756e-02, 4.005695840052305e-02, 6.443346248735778e-03, -2.149050883068006e-02, -1.222541607918958e-02, 8.039540142470502e-03, 1.021174072452739e-02, -7.291933574932576e-04, -5.915356487278223e-03, -1.761657712050434e-03, 2.386365413757806e-03, 1.669304111936031e-03, -5.202488037993005e-04, -8.485164630872996e-04, -5.918660218780589e-05, 2.370265491629509e-04, 6.142752443864771e-05, -1.553410708509952e-05, 1.742673394214716e-19, 
  /*
   フィルタ長 : N = 63
   フィルタの種類 : LPF
   窓の種類 : Blackman窓
   正規化遮断周波数 : 0.25
   */
    //1.424979695996199e-19, 5.305367267308876e-20, 4.117891911403497e-05, -1.674546853619076e-19, -1.843656486130333e-04, -6.035497105869447e-19, 4.762259624106090e-04, -1.027853593121634e-18, -9.890387350449743e-04, 6.656556143708382e-18, 1.823255726441820e-03, -2.939892936396533e-18, -3.110167763743626e-03, 4.380102905423817e-18, 5.017218602192004e-03, -6.141294310628161e-18, -7.761138566242649e-03, 8.174130081174207e-18, 1.163982215038885e-02, -1.038769191647441e-17, -1.710853704321617e-02, 1.265444953125003e-17, 2.496967007717532e-02, -1.482146377666390e-17, -3.690090496066861e-02, 1.672639538905066e-17, 5.726333920921481e-02, -1.821608406461116e-17, -1.021489002185485e-01, 1.916500309615292e-17, 3.169720478745973e-01, 4.999999999999999e-01, 3.169720478745973e-01, 1.916500309615292e-17, -1.021489002185485e-01, -1.821608406461116e-17, 5.726333920921481e-02, 1.672639538905066e-17, -3.690090496066861e-02, -1.482146377666390e-17, 2.496967007717532e-02, 1.265444953125003e-17, -1.710853704321617e-02, -1.038769191647441e-17, 1.163982215038885e-02, 8.174130081174207e-18, -7.761138566242649e-03, -6.141294310628161e-18, 5.017218602192004e-03, 4.380102905423817e-18, -3.110167763743626e-03, -2.939892936396533e-18, 1.823255726441820e-03, 6.656556143708382e-18, -9.890387350449743e-04, -1.027853593121634e-18, 4.762259624106090e-04, -6.035497105869447e-19, -1.843656486130333e-04, -1.674546853619076e-19, 4.117891911403497e-05, 5.305367267308876e-20, 1.424979695996199e-19, 
  /*
フィルタ長 : N = 31
   フィルタの種類 : LPF
   窓の種類 : Blackman窓
   正規化遮断周波数 : 0.05
   */
    2.944958038392145e-19, -8.670717849467505e-05, -3.319550967880867e-04, -6.269783635101152e-04, -6.891897353101802e-04, 5.067623382275192e-19, 2.194265176660287e-03, 6.770228567408323e-03, 1.449504765874971e-02, 2.572136877875045e-02, 4.010704565915763e-02, 5.647463951586574e-02, 7.289735515160392e-02, 8.702886530667454e-02, 9.660811335016214e-02, 9.999999999999999e-02, 9.660811335016214e-02, 8.702886530667454e-02, 7.289735515160392e-02, 5.647463951586574e-02, 4.010704565915763e-02, 2.572136877875045e-02, 1.449504765874971e-02, 6.770228567408323e-03, 2.194265176660287e-03, 5.067623382275192e-19, -6.891897353101802e-04, -6.269783635101152e-04, -3.319550967880867e-04, -8.670717849467505e-05, 2.944958038392145e-19, 
  };

  if (use_analog_filter) {
    I = low_pass_filter(I, dot_clock_frequency, 0.7 * 1000 * 1000, 1);
  } else {
    I = fir_filter(I, I_lowpass_coefficient);
    //I = fir_filter(I, new double[] {0.25, 0.25, 0.25, 0.25});
  }

  double[] Q_lowpass_coefficient = {
  /*
   フィルタ長 : N = 63
   フィルタの種類 : LPF
   窓の種類 : Hamming
   正規化遮断周波数 : 0.0349206 (0.5MHz)
   */
    //4.072206056087307e-04, 2.576345551862138e-04, 7.828851824217711e-05, -1.598757525420035e-04, -4.857436020318563e-04, -9.222735013243808e-04, -1.480589379552482e-03, -2.154558981334887e-03, -2.916495865290516e-03, -3.714558464630662e-03, -4.472296698955755e-03, -5.090623907683578e-03, -5.452283255688842e-03, -5.428650923631795e-03, -4.888493304755696e-03, -3.708092575635594e-03, -1.781993554946133e-03, 9.664792171991495e-04, 4.575820306097140e-03, 9.038904692053897e-03, 1.429824470228926e-02, 2.024449559857712e-02, 2.671852929770288e-02, 3.351712687849373e-02, 4.040205809165544e-02, 4.711204333404952e-02, 5.337685342197266e-02, 5.893261559782899e-02, 6.353727697397493e-02, 6.698513987453367e-02, 6.911943148270779e-02, 6.984200000000000e-02, 6.911943148270779e-02, 6.698513987453367e-02, 6.353727697397493e-02, 5.893261559782899e-02, 5.337685342197266e-02, 4.711204333404952e-02, 4.040205809165544e-02, 3.351712687849373e-02, 2.671852929770288e-02, 2.024449559857712e-02, 1.429824470228926e-02, 9.038904692053897e-03, 4.575820306097140e-03, 9.664792171991495e-04, -1.781993554946133e-03, -3.708092575635594e-03, -4.888493304755696e-03, -5.428650923631795e-03, -5.452283255688842e-03, -5.090623907683578e-03, -4.472296698955755e-03, -3.714558464630662e-03, -2.916495865290516e-03, -2.154558981334887e-03, -1.480589379552482e-03, -9.222735013243808e-04, -4.857436020318563e-04, -1.598757525420035e-04, 7.828851824217711e-05, 2.576345551862138e-04, 4.072206056087307e-04, 
  /*
  フィルタ長 : N = 47
   フィルタの種類 : LPF
   窓の種類 : Blackman窓
   正規化遮断周波数 : 0.0698412 (1MHz)
   */
    //1.189928348120646e-19, -5.560347624307711e-06, 2.173256578853548e-05, 1.537509659767198e-04, 4.389439743359668e-04, 8.554073388440999e-04, 1.266710951322840e-03, 1.403687299378961e-03, 8.995870680856238e-04, -6.029110184142522e-04, -3.278484701527538e-03, -6.919052493055706e-03, -1.077635929765276e-02, -1.352822903668567e-02, -1.343050290985220e-02, -8.666588026557091e-03, 2.162259924845335e-03, 1.952731598453369e-02, 4.259930214989702e-02, 6.915374446198817e-02, 9.583162388614053e-02, 1.187322119801473e-01, 1.342109187297998e-01, 1.396820000000000e-01, 1.342109187297998e-01, 1.187322119801473e-01, 9.583162388614053e-02, 6.915374446198817e-02, 4.259930214989702e-02, 1.952731598453369e-02, 2.162259924845335e-03, -8.666588026557091e-03, -1.343050290985220e-02, -1.352822903668567e-02, -1.077635929765276e-02, -6.919052493055706e-03, -3.278484701527538e-03, -6.029110184142522e-04, 8.995870680856238e-04, 1.403687299378961e-03, 1.266710951322840e-03, 8.554073388440999e-04, 4.389439743359668e-04, 1.537509659767198e-04, 2.173256578853548e-05, -5.560347624307711e-06, 1.189928348120646e-19, 
  /*
   フィルタ長 : N = 63
   フィルタの種類 : LPF
   窓の種類 : Blackman窓
   正規化遮断周波数 : 0.25
   */
    //1.424979695996199e-19, 5.305367267308876e-20, 4.117891911403497e-05, -1.674546853619076e-19, -1.843656486130333e-04, -6.035497105869447e-19, 4.762259624106090e-04, -1.027853593121634e-18, -9.890387350449743e-04, 6.656556143708382e-18, 1.823255726441820e-03, -2.939892936396533e-18, -3.110167763743626e-03, 4.380102905423817e-18, 5.017218602192004e-03, -6.141294310628161e-18, -7.761138566242649e-03, 8.174130081174207e-18, 1.163982215038885e-02, -1.038769191647441e-17, -1.710853704321617e-02, 1.265444953125003e-17, 2.496967007717532e-02, -1.482146377666390e-17, -3.690090496066861e-02, 1.672639538905066e-17, 5.726333920921481e-02, -1.821608406461116e-17, -1.021489002185485e-01, 1.916500309615292e-17, 3.169720478745973e-01, 4.999999999999999e-01, 3.169720478745973e-01, 1.916500309615292e-17, -1.021489002185485e-01, -1.821608406461116e-17, 5.726333920921481e-02, 1.672639538905066e-17, -3.690090496066861e-02, -1.482146377666390e-17, 2.496967007717532e-02, 1.265444953125003e-17, -1.710853704321617e-02, -1.038769191647441e-17, 1.163982215038885e-02, 8.174130081174207e-18, -7.761138566242649e-03, -6.141294310628161e-18, 5.017218602192004e-03, 4.380102905423817e-18, -3.110167763743626e-03, -2.939892936396533e-18, 1.823255726441820e-03, 6.656556143708382e-18, -9.890387350449743e-04, -1.027853593121634e-18, 4.762259624106090e-04, -6.035497105869447e-19, -1.843656486130333e-04, -1.674546853619076e-19, 4.117891911403497e-05, 5.305367267308876e-20, 1.424979695996199e-19, 
  /*
フィルタ長 : N = 31
   フィルタの種類 : LPF
   窓の種類 : Blackman窓
   正規化遮断周波数 : 0.05
   */
    2.944958038392145e-19, -8.670717849467505e-05, -3.319550967880867e-04, -6.269783635101152e-04, -6.891897353101802e-04, 5.067623382275192e-19, 2.194265176660287e-03, 6.770228567408323e-03, 1.449504765874971e-02, 2.572136877875045e-02, 4.010704565915763e-02, 5.647463951586574e-02, 7.289735515160392e-02, 8.702886530667454e-02, 9.660811335016214e-02, 9.999999999999999e-02, 9.660811335016214e-02, 8.702886530667454e-02, 7.289735515160392e-02, 5.647463951586574e-02, 4.010704565915763e-02, 2.572136877875045e-02, 1.449504765874971e-02, 6.770228567408323e-03, 2.194265176660287e-03, 5.067623382275192e-19, -6.891897353101802e-04, -6.269783635101152e-04, -3.319550967880867e-04, -8.670717849467505e-05, 2.944958038392145e-19, 
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

  double black_level = 0;
  double black_level_lowpass_cutoff = (double)(1000 * 1000) / dot_clock_frequency;

  double burst_smooth_cutoff = dot_clock_frequency / (1 * 1000 * 1000);

  signal[] out = new signal[in.length];
  for (int i = 0; i < in.length; i++) {

    if (sync[i].burst && !sync[i].V_sync) {
      //基準色相
      burst_I = (I[i] + burst_I * burst_smooth_cutoff) / (burst_smooth_cutoff + 1);
      burst_Q = (Q[i] + burst_Q * burst_smooth_cutoff) / (burst_smooth_cutoff + 1);

      chroma_level = Math.sqrt((burst_I * burst_I) + (burst_Q * burst_Q));

      //基準黒レベル
      black_level += (Y[i] - black_level) * black_level_lowpass_cutoff;

      if (chroma_level > 0.1) {
        burst_hue = Math.atan2(-burst_I, -burst_Q) + ((double)33 / 360 * TWO_PI);
        //burst_hue = Math.atan2(-burst_I, -burst_Q) + ((double)-90 / 360 * TWO_PI);
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

    I[i] /= 1 / saturation * chroma_level / 0.792 * 3;
    Q[i] /= 1 / saturation * chroma_level / 0.792 * 3;

    //out[i] = in[i];//その他の情報は保持
    out[i] = new signal();
    out[i].Y = Y[i];
    out[i].I = I[i];
    out[i].Q = Q[i];

    out[i].H_sync = sync[i].H_sync;
    out[i].V_sync = sync[i].V_sync;
    out[i].composite_sync = sync[i].composite_sync;
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
    if (gamma) {
      RGB[0] = gamma(RGB[0], 2.2);
      RGB[1] = gamma(RGB[1], 2.2);
      RGB[2] = gamma(RGB[2], 2.2);
    }
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
  }
  return out;
}

PImage rgb_to_image(signal[] in, deinterlace_mode mode) {
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

  int field = -1;//最初に垂直同期が来るから
  int frame = 0;

  for (int i = 0; i < in.length; i++) {
    /*
    int x = i % width;
     int y = i / width;
     
     int field = (int)Math.floor((double)y / ntsc_vertical_field_number_of_line);
     int frame = (int)Math.floor((double)y / ntsc_vertical_frame_number_of_line);
     
     if (mode == deinterlace_mode.DEINTERLACE_WEAVE) {
     //単純なインターレース解除
     //奇数、偶数の順番に送られてくる
     y = (int)Math.floor((y - ((double)field * ntsc_vertical_field_number_of_line)) * 2);
     y += Math.floor((frame * ntsc_vertical_frame_number_of_line));
     }
     */

    x += 1;
    if (h_sync_prev == false && in[i].H_sync) {
      //水平同期の立ち上がりでyに2を足す
      //println("hsync");
      y += 2;
      x = 0;
    }

    if (v_sync_prev == false && in[i].V_sync) {
      //垂直同期の立ち上がりでフィールドカウンターを+1
      field++;
      if (field > 1) {
        frame++;
        field = 0;
        //2フィールドで1フレーム 奇数偶数の計算はしてないから最悪
      }
      x = 0;
      y = (frame * (int)ntsc_vertical_frame_number_of_line) + field;
      //println(field, frame);//デバッグ用
    }

    h_sync_prev = in[i].H_sync;
    v_sync_prev = in[i].V_sync;

    color c = color(0, 255, 0);

    //in[i].R = in[i].G = in[i].B = 0.5;
    double R = in[i].R;
    double G = in[i].G;
    double B = in[i].B;

    c = color((float)(R * 255), (float)(G * 255), (float)(B * 255));

    out.set(x, y, c);
  }
  return out;
}
