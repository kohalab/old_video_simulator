double[] RGB_to_YUV(double[] in) {
  //inはガンマ補正済みのRGB
  //BT.470
  double WR = 0.299;
  double WB = 0.114;
  double WG = 1 - WR - WB;

  double Umax = 0.436;
  double Vmax = 0.615;

  double Y = in[0] * WR + in[1] * WG + in[2] * WB;
  double U = Umax * ((in[2] - Y) / (1 - WB));
  double V = Vmax * ((in[0] - Y) / (1 - WR));

  //Yの範囲は0 ~ 1
  //Uの範囲は-Umax ~ Umax
  //Vの範囲は-Vmax ~ Vmax
  return (new double[] {Y, U, V});
}

double[] YUV_to_RGB(double[] in) {
  //inはYUV
  //BT.470
  double WR = 0.299;
  double WB = 0.114;
  double WG = 1 - WR - WB;

  double Umax = 0.436;
  double Vmax = 0.615;

  double R = in[0] + (in[2] * ((1 - WR) / Vmax));
  double G = in[0] - (in[1] * ((WB * (1 - WB)) / (Umax * WG))) - (in[2] * ((WR * (1 - WR)) / (Vmax * WG)));
  double B = in[0] + (in[1] * ((1 - WB) / Umax));

  //RGBの範囲は0 ~ 1のはず
  return (new double[] {R, G, B});
}


double[] RGB_to_YIQ(double[] in) {
  //inはRGB 範囲は0 ~ 1

  //NTSC
  double Y = in[0] * 0.299  + in[1] * 0.587  + in[2] * 0.114 ;
  
  double I = in[0] * 0.5959 - in[1] * 0.2746 - in[2] * 0.3213;
  double Q = in[0] * 0.2115 - in[1] * 0.5227 + in[2] * 0.3112;
  
  //double I = 0.493 * (in[2] - Y);
  //double Q = 0.877 * (in[0] - Y);

  //Yの範囲は0 ~ 1
  //Iの範囲は-0.5957 ~ 0.5957
  //Qの範囲は-0.5226 ~ 0.5226
  return (new double[] {Y, I, Q});
}

double[] YIQ_to_RGB(double[] in) {
  //inはYIQ

  //NTSC

  double R = in[0] + in[1] * 0.956 + in[2] * 0.619;
  double G = in[0] - in[1] * 0.272 - in[2] * 0.647;
  double B = in[0] - in[1] * 1.106 + in[2] * 1.703;

  //RGBの範囲は0 ~ 1のはず
  return (new double[] {R, G, B});
}

double sRGB_gamma(double in) {
  if (in <= 0.0031308d) {
    return in * 12.92d;
  } else {
    return 1.055d * Math.pow(in, 1.0d / 2.4d) - 0.055d;
  }
}

double sRGB_degamma(double in) {
  if (in <= 0.04045d) {
    return in / 12.92d;
  } else {
    return Math.pow((in + 0.055d) / 1.055d, 2.4d);
  }
}


double gamma(double in, double gamma) {
  //inの範囲は0 ~ 1
  //gamma値が大きいほど暗くなる
  //ブラウン管のガンマ値は2.2らしい
  if (in < 0)in = 0;
  if (in > 1)in = 1;
  return Math.pow(in, gamma);
}
