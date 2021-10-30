//https://vstcpp.wpblog.jp/?page_id=523
//ここに書いてある

//ローパスフィルタ を直列でつなぐ場合は、
//2直列ならHz * 1.25
//3直列ならHz * 1.4375
//4直列ならHz * 1.625
//ハイパスフィルタなら * が / になる
//で-3dB時点のカットオフを計算できる

boolean de_delay = false;

double[] filter(double[] in, double a0, double a1, double a2, double b0, double b1, double b2, int delay) {
  if (in == null) {
    return null;
  }
  if (in.length == 0) {
    return new double[0];
  }
  double[] input = new double[in.length];
  for (int i = 0; i < in.length; i++) {
    int index = i + delay;
    if (index > in.length - 1)index = in.length - 1;
    input[i] = in[index];
  }
  double[] out = new double[in.length];

  double in1 = 0, in2 = 0, out1 = 0, out2 = 0;

  for (int i = 0; i < in.length; i++) {
    // 入力信号にフィルタを適用し、出力信号として書き出す。
    out[i] = b0/a0 * input[i] + b1/a0 * in1  + b2/a0 * in2
      - a1/a0 * out1 - a2/a0 * out2;

    in2  = in1;       // 2つ前の入力信号を更新
    in1  = input[i];  // 1つ前の入力信号を更新

    out2 = out1;   // 2つ前の出力信号を更新
    out1 = out[i]; // 1つ前の出力信号を更新
  }
  return out;
}

double[] low_pass_filter(double[] in, double samplerate, double frequency, double q) {
  //カットオフ周波数ではqは1/sqrt(2)だと-3db
  //qが1だとカットオフ周波数で0db
  double omega = 2.0d * Math.PI * frequency / samplerate;
  double alpha = Math.sin(omega) / (2.0d * q);

  double a0 =  1.0d + alpha;
  double a1 = -2.0d * Math.cos(omega);
  double a2 =  1.0d - alpha;
  double b0 = (1.0d - Math.cos(omega)) / 2.0d;
  double b1 =  1.0d - Math.cos(omega);
  double b2 = (1.0d - Math.cos(omega)) / 2.0d;
  return filter(in, a0, a1, a2, b0, b1, b2, de_delay?2:0);
}

double[] high_pass_filter(double[] in, double samplerate, double frequency, double q) {
  //カットオフ周波数ではqは1/sqrt(2)だと-3db
  //qが1だとカットオフ周波数で0db
  double omega = 2.0d * Math.PI * frequency / samplerate;
  double alpha = Math.sin(omega) / (2.0f * q);

  double a0 =   1.0d + alpha;
  double a1 =  -2.0d * Math.cos(omega);
  double a2 =   1.0d - alpha;
  double b0 =  (1.0d + Math.cos(omega)) / 2.0d;
  double b1 = -(1.0d + Math.cos(omega));
  double b2 =  (1.0d + Math.cos(omega)) / 2.0d;
  return filter(in, a0, a1, a2, b0, b1, b2, de_delay?2:0);
}

double[] band_pass_filter(double[] in, double samplerate, double frequency, double band_width) {
  //band_widthはオクターブ 1なら1オクターブあたり-3dB
  double omega = 2.0d * Math.PI * frequency / samplerate;
  double alpha = Math.sin(omega) * Math.sinh(Math.log(2.0d) / 2.0 * band_width * omega / Math.sin(omega));

  double a0 =  1.0d + alpha;
  double a1 = -2.0d * Math.cos(omega);
  double a2 =  1.0d - alpha;
  double b0 =  alpha;
  double b1 =  0.0d;
  double b2 = -alpha;
  return filter(in, a0, a1, a2, b0, b1, b2, 0);
}

double[] notch_filter(double[] in, double samplerate, double frequency, double band_width) {
  //band_widthはオクターブ 1なら1オクターブあたり-6dB
  double omega = 2.0d * Math.PI * frequency / samplerate;
  double alpha = Math.sin(omega) * Math.sinh(log(2.0f) / 2.0 * band_width * omega / Math.sin(omega));

  double a0 =  1.0d + alpha;
  double a1 = -2.0d * Math.cos(omega);
  double a2 =  1.0d - alpha;
  double b0 =  1.0d;
  double b1 = -2.0d * Math.cos(omega);
  double b2 =  1.0d;
  return filter(in, a0, a1, a2, b0, b1, b2, 0);
}

/*
FIRフィルタの窓関数法による設計 　～入力画面～
 http://dsp.jpn.org/dfdesign/fir/mado.shtml
 */
double[] fir_filter(double[] in, double[] coefficient) {
  double[] out = new double[in.length];
  for (int i = 0; i < in.length; i++) {
    double a = 0;
    for (int f = 0; f < coefficient.length; f++) {
      if (i - f + (coefficient.length / 2) >= 0 && i - f + (coefficient.length / 2) < in.length) {
        a += in[i - f + (coefficient.length / 2)] * coefficient[f];
      }
    }
    out[i] = a;
  }
  return out;
}

double[] fir_filter(double[] in, double[] coefficient, int coefficient_period) {
  double[] out = new double[in.length];
  for (int i = 0; i < in.length; i++) {
    double a = 0;
    for (int f = 0; f < coefficient.length; f++) {
      if (i + (f - (coefficient.length / 2)) * coefficient_period >= 0 && i + (f - (coefficient.length / 2)) * coefficient_period < in.length) {
        a += in[i + (f - (coefficient.length / 2)) * coefficient_period] * coefficient[f];
      }
    }
    out[i] = a;
  }
  return out;
}


double[] comb_filter(double[] in, int length) {
  double[] out = new double[in.length];
  for (int i = 0; i < in.length; i++) {
    double a = in[i];
    if (i - length >= 0) {
      a += in[i - length];
    }
    out[i] = a / 2;
  }
  return out;
}

double[] delay_filter(double[] in, int length) {
  double[] out = new double[in.length];
  for (int i = 0; i < in.length; i++) {
    double a = 0;
    if (i + length < in.length) {
      a = in[i + length];
    }
    out[i] = a;
  }
  return out;
}

double[] add(double[] inA, double[] inB, double aA, double aB) {
  double[] out = new double[inA.length];
  for (int i = 0; i < inA.length; i++) {
    out[i] = inA[i] * aA + inB[i] * aB;
  }
  return out;
}

double[] add(double[] inA, double[] inB) {
  return add(inA, inB, 1, 1);
}
