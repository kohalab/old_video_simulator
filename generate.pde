boolean gamma = false;

class signal {
  double R, G, B;
  double Y, I, Q;
  double C;
  double composite;
  boolean H_sync, V_sync, composite_sync, burst;//正論理
}

signal[] generate(PImage[] in, PImage[] composite_in, int field_length) {
  int length = (int)((1 / ntsc_vertical_frequency) * field_length * dot_clock_frequency);
  signal[] out = new signal[length];
  for (int i = 0; i < length; i++) {
    out[i] = new signal();
    //double v_counter = (((double)i * ntsc_vertical_frequency / dot_clock_frequency)) * ntsc_vertical_number_of_line;
    //double h_counter = ((double)i * ntsc_horizontal_frequency / dot_clock_frequency) - Math.floor(v_counter);

    double h_counter = ((double)i * ntsc_horizontal_frequency / dot_clock_frequency) % 1;
    double v_counter = Math.floor((double)i * ntsc_horizontal_frequency / dot_clock_frequency);

    double line_field = Math.floor(((double)i * ntsc_vertical_frequency * ntsc_vertical_field_number_of_line / dot_clock_frequency) % ntsc_vertical_field_number_of_line);
    double line_frame = Math.floor(((double)i * ntsc_vertical_frequency * ntsc_vertical_field_number_of_line / dot_clock_frequency) % ntsc_vertical_frame_number_of_line);
    int integer_field_line = (int)Math.floor(line_frame) % (int)Math.floor(ntsc_vertical_field_number_of_line);
    //double v_counter = (double)Math.floor((double)i * ntsc_horizontal_frequency / dot_clock_frequency) % ntsc_vertical_field_number_of_line;
    /*
    if (i % 500 == 499) {
     println(v_counter, line_field);
     }
     */

    int field = (int)((double)Math.floor(v_counter) / ntsc_vertical_field_number_of_line);

    PImage img = in[field];


    boolean h_sync = h_counter < (ntsc_horizontal_sync_pulse_end * ntsc_horizontal_frequency);
    boolean v_equalizing_sync = (line_field >= ntsc_vertical_equalizing_sync_start_line) && (line_field <= ntsc_vertical_equalizing_sync_end_line);
    boolean v_sync = (line_field >= ntsc_vertical_sync_start_line) && (line_field <= ntsc_vertical_sync_end_line);
    boolean burst = (h_counter > (ntsc_horizontal_color_burst_start / (1 / ntsc_horizontal_frequency)));
    burst &= (h_counter < (ntsc_horizontal_color_burst_end / (1 / ntsc_horizontal_frequency)));
    double h_visible_counter = (h_counter - (ntsc_horizontal_view_start / ntsc_horizontal_end)) / ((ntsc_horizontal_view_end - ntsc_horizontal_view_start) / ntsc_horizontal_end);
    //double v_visible_counter = Math.floor(v_counter) / (ntsc_vertical_field_number_of_line - 1);
    double v_visible_counter = ((double)Math.floor(v_counter) % ntsc_vertical_field_number_of_line) / (ntsc_vertical_field_number_of_line - 1);

    out[i].R = 0;
    out[i].G = 0;
    out[i].B = 0;

    if (!v_sync && !v_equalizing_sync && h_visible_counter >= 0 && h_visible_counter <= 1) {
      if (test_line) {
        if (integer_field_line >= 15 && integer_field_line < 16) {
          //スイープ信号
          double phase = Math.pow(h_visible_counter, 3) * ntsc_horizontal_number_of_color_cycle / 3;
          out[i].composite = (Math.sin(phase * TWO_PI) / 2) + 0.5;//後々ガンマされるから逆ガンマしとく
        } else if (integer_field_line >= 16 && integer_field_line < 17) {
          //矩形スイープ信号
          double phase = Math.pow(h_visible_counter, 3) * ntsc_horizontal_number_of_color_cycle / 3 / 10;
          double a = (Math.sin(phase * TWO_PI) / 2) + 0.5;
          if (a > 0.5) {
            a = 1;
          } else {
            a = 0;
          }
          out[i].composite = a;//後々ガンマされるから逆ガンマしとく
        } else if (integer_field_line >= 17 && integer_field_line < 18) {
          //断続カラーバー
          int c = 7 - (int)Math.floor(h_visible_counter * 8) % 8;
          if ((int)Math.floor(h_visible_counter * 16) % 2 != 0) {
            out[i].R = (c & (1 << 1)) != 0 ? 1 : 0;
            out[i].G = (c & (1 << 2)) != 0 ? 1 : 0;
            out[i].B = (c & (1 << 0)) != 0 ? 1 : 0;
          }
        } else if (integer_field_line >= 18 && integer_field_line < 19) {
          //リニアランプ
          out[i].R = out[i].G = out[i].B = gamma(h_visible_counter, 2.2);//後々ガンマされるから逆ガンマしとく
        } else if (integer_field_line >= 19 && integer_field_line < 20) {
          //カラーバー
          int c = 7 - (int)Math.floor(h_visible_counter * 8) % 8;
          out[i].R = (c & (1 << 1)) != 0 ? 1 : 0;
          out[i].G = (c & (1 << 2)) != 0 ? 1 : 0;
          out[i].B = (c & (1 << 0)) != 0 ? 1 : 0;
        }
      }
      if (integer_field_line >= 20) {
        if (line_field >= Math.round(ntsc_vertical_view_start) && line_field <= Math.round(ntsc_vertical_view_end)) {
          int x = (int)((double)h_visible_counter * (img.width + 1));// +1 が大事
          int y = (int)((double)v_visible_counter * (img.height - 1));// -1 が大事
          if (x > img.width - 1) {
            x = img.width - 1;
          }
          if (y > img.height - 1) {
            y = img.height - 1;
          }
          color c = img.get(x, y);
          /*
          if (c >> 16 == 0) {
           println("error! is alpha "+(int)((double)h_visible_counter * img.width), (int)((double)v_visible_counter * (img.height - 1)));
           }
           */
          double R = (double)((c >> 16) & 0xff) / 255;
          double G = (double)((c >> 8) & 0xff) / 255;
          double B = (double)((c >> 0) & 0xff) / 255;
          if (gamma) {          
            R = sRGB_degamma(R);
            G = sRGB_degamma(G);
            B = sRGB_degamma(B);
          }

          double edge_time = ntsc_horizontal_view_edge / ntsc_horizontal_end;
          double view_start_time = ntsc_horizontal_view_start / ntsc_horizontal_end;
          double view_end_time = ntsc_horizontal_view_end / ntsc_horizontal_end;
          double amp = 1;

          if (h_counter < view_start_time + edge_time) {
            amp = (h_counter - view_start_time) / edge_time;
          }
          if (h_counter > view_end_time - edge_time) {
            amp = (view_end_time - h_counter) / edge_time;
          }


          out[i].R = R * amp;
          out[i].G = G * amp;
          out[i].B = B * amp;
          //println(hex(c));
          if ((composite_in != null) && composite_in[field] != null) {
            double C = (double)(composite_in[field].get(x, y) & 0xff) / 255;
            out[i].composite += gamma(sRGB_degamma(C), 2.2) * amp * ntsc_luminance_level;
          }
        }
      }
    }


    out[i].H_sync = h_sync;
    out[i].V_sync = v_sync;

    if (!v_sync && !v_equalizing_sync) {
      out[i].burst = burst;
    }

    //composite_sync generation
    if (v_sync || v_equalizing_sync) {

      if (v_sync) {       
        if (
          h_counter % 0.5 >= ntsc_horizontal_serrated_sync_pulse_start * ntsc_horizontal_frequency && 
          h_counter % 0.5 <= ntsc_horizontal_serrated_sync_pulse_end * ntsc_horizontal_frequency) {
          out[i].composite_sync = true;
        } else {
          out[i].composite_sync = false;
        }
      } else if (v_equalizing_sync) {

        if (
          h_counter % 0.5 >= ntsc_horizontal_equalizing_sync_pulse_start * ntsc_horizontal_frequency && 
          h_counter % 0.5 <= ntsc_horizontal_equalizing_sync_pulse_end * ntsc_horizontal_frequency) {
          out[i].composite_sync = true;
        } else {
          out[i].composite_sync = false;
        }
      }
    } else {
      out[i].composite_sync = h_sync;
    }
  }
  return out;
}

signal[] encode_rgb_to_yuv(signal[] in) {
  signal[] out = new signal[in.length];
  for (int i = 0; i < in.length; i++) {
    //out[i] = new signal();
    out[i] = in[i];
    out[i].Y = 0;
    out[i].I = 0;
    out[i].Q = 0;
    if (gamma) {
      in[i].R = gamma(in[i].R, 1 / 2.2);
      in[i].G = gamma(in[i].G, 1 / 2.2);
      in[i].B = gamma(in[i].B, 1 / 2.2);
    }
    double[] YIQ = RGB_to_YIQ(new double[] {in[i].R, in[i].G, in[i].B});
    out[i].Y = YIQ[0] * ntsc_luminance_level;
    out[i].I = in[i].I + YIQ[1];
    out[i].Q = in[i].Q + YIQ[2];

    out[i].composite = in[i].composite;
  }

  double[] filter_in = new double[in.length];
  for (int i = 0; i < in.length; i++) {
    filter_in[i] = out[i].Y;
  }

  //filter_in =  filter_in = low_pass_filter(filter_in, dot_clock_frequency, 3 * 1000 * 1000, 1 / Math.sqrt(2));//遅延;
  //filter_in = low_pass_filter(filter_in, dot_clock_frequency, 3.2 * 1000 * 1000, 1 / Math.sqrt(2));//遅延
  //filter_in = low_pass_filter(filter_in, dot_clock_frequency, 3.2 * 1000 * 1000, 1 / Math.sqrt(2));//遅延
  //filter_in = low_pass_filter(filter_in, dot_clock_frequency, 3.2 * 1000 * 1000, 0.5 / Math.sqrt(2));//遅延

  //filter_in = band_pass_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 0.3);


  for (int i = 0; i < in.length; i++) {
    out[i].Y = filter_in[i];
  }
  for (int i = 0; i < in.length; i++) {
    filter_in[i] = out[i].I;
  }
  double[] I_lowpass_coefficient = {
  /*
  フィルタ長 : N = 47
   フィルタの種類 : LPF
   窓の種類 : Kaiser窓
   正規化遮断周波数 : 0.0977778 (1.4MHz)
   阻止域減衰量 : 96 [dB]
   */
    7.042265373217540e-06, 
    2.500534958598106e-05, 
    2.684855436953397e-05, 
    -4.870151961045935e-05, 
    -2.642500008866264e-04, 
    -5.977256226339406e-04, 
    -8.468742470612364e-04, 
    -6.193367248521860e-04, 
    4.965951841854623e-04, 
    2.576362181563825e-03, 
    4.975296584711108e-03, 
    6.209675462757700e-03, 
    4.382769502429129e-03, 
    -1.795746378440415e-03, 
    -1.173400552633058e-02, 
    -2.209721431127556e-02, 
    -2.706991444775909e-02, 
    -2.005704056459013e-02, 
    3.572004544367134e-03, 
    4.378115141821761e-02, 
    9.454787097719979e-02, 
    1.448504903389269e-01, 
    1.819113614967875e-01, 
    1.955560000000000e-01, 
    1.819113614967875e-01, 
    1.448504903389269e-01, 
    9.454787097719979e-02, 
    4.378115141821761e-02, 
    3.572004544367134e-03, 
    -2.005704056459013e-02, 
    -2.706991444775909e-02, 
    -2.209721431127556e-02, 
    -1.173400552633058e-02, 
    -1.795746378440415e-03, 
    4.382769502429129e-03, 
    6.209675462757700e-03, 
    4.975296584711108e-03, 
    2.576362181563825e-03, 
    4.965951841854623e-04, 
    -6.193367248521860e-04, 
    -8.468742470612364e-04, 
    -5.977256226339406e-04, 
    -2.642500008866264e-04, 
    -4.870151961045935e-05, 
    2.684855436953397e-05, 
    2.500534958598106e-05, 
    7.042265373217540e-06, 
  };
  filter_in = fir_filter(filter_in, I_lowpass_coefficient);

  //filter_in = low_pass_filter(filter_in, dot_clock_frequency, 1.5 * 1000 * 1000, 1 / Math.sqrt(2));
  for (int i = 0; i < in.length; i++) {
    out[i].I = filter_in[i];
  }
  for (int i = 0; i < in.length; i++) {
    filter_in[i] = out[i].Q;
  }
  double[] Q_lowpass_coefficient = {
  /*
 フィルタ長 : N = 47
   フィルタの種類 : LPF
   窓の種類 : Kaiser窓
   正規化遮断周波数 : 0.0279365 (0.4MHz)
   阻止域減衰量 : 63 [dB]
   */
    -1.630498521453600e-04, 
    -2.763861049679442e-04, 
    -3.726142472964665e-04, 
    -4.077206343830302e-04, 
    -3.222077820247535e-04, 
    -4.263615512728610e-05, 
    5.148124206216985e-04, 
    1.438763504771806e-03, 
    2.815331745273425e-03, 
    4.719564343372289e-03, 
    7.206372453620561e-03, 
    1.030183275298108e-02, 
    1.399581061866077e-02, 
    1.823682205719539e-02, 
    2.292990880459907e-02, 
    2.793805810670735e-02, 
    3.308737676200490e-02, 
    3.817586023154372e-02, 
    4.298522167733436e-02, 
    4.729490528026169e-02, 
    5.089714345133962e-02, 
    5.361176159642464e-02, 
    5.529940830394552e-02, 
    5.587200000000000e-02, 
    5.529940830394552e-02, 
    5.361176159642464e-02, 
    5.089714345133962e-02, 
    4.729490528026169e-02, 
    4.298522167733436e-02, 
    3.817586023154372e-02, 
    3.308737676200490e-02, 
    2.793805810670735e-02, 
    2.292990880459907e-02, 
    1.823682205719539e-02, 
    1.399581061866077e-02, 
    1.030183275298108e-02, 
    7.206372453620561e-03, 
    4.719564343372289e-03, 
    2.815331745273425e-03, 
    1.438763504771806e-03, 
    5.148124206216985e-04, 
    -4.263615512728610e-05, 
    -3.222077820247535e-04, 
    -4.077206343830302e-04, 
    -3.726142472964665e-04, 
    -2.763861049679442e-04, 
    -1.630498521453600e-04, 
  };
  filter_in = fir_filter(filter_in, Q_lowpass_coefficient);

  //filter_in = low_pass_filter(filter_in, dot_clock_frequency, 0.5 * 1000 * 1000, 1 / Math.sqrt(2));
  for (int i = 0; i < in.length; i++) {
    out[i].Q = filter_in[i];
  }
  /*
  for (int i = 0; i < in.length; i++) {
   out[i].composite = in[i].composite;
   }
   */
  return out;
}

signal[] encode_rgb_to_ntsc(signal[] in) {
  return encode_yuv_to_ntsc(encode_rgb_to_yuv(in));
}
signal[] encode_yuv_to_ntsc(signal[] in) {
  signal[] out = new signal[in.length];
  /*
  for (int i = 0; i < in.length; i++) {
   out[i] = new signal();
   if (gamma) {
   in[i].R = gamma(in[i].R, 1 / 2.2);
   in[i].G = gamma(in[i].G, 1 / 2.2);
   in[i].B = gamma(in[i].B, 1 / 2.2);
   }
   double[] YIQ = RGB_to_YIQ(new double[] {in[i].R, in[i].G, in[i].B});
   out[i].Y = YIQ[0] * ntsc_luminance_level;
   out[i].I = in[i].I + YIQ[1];
   out[i].Q = in[i].Q + YIQ[2];
   }
   */

  for (int i = 0; i < in.length; i++) {
    out[i] = new signal();
    out[i].Y += in[i].Y + (in[i].composite_sync ? ntsc_sync_level : 0);

    //ntsc_color_burst_levelはピークtoピークなのに/2するとレベルが低く見える
    //IとQのレベルは正しいのか？
    out[i].C = (in[i].burst ? Math.sin(i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) : 0) * ntsc_color_burst_level;

    out[i].C += in[i].I * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) + ((double)57 / 360 * Math.PI * 2));
    out[i].C += in[i].Q * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) + ((double)147 / 360 * Math.PI * 2));
    /*
    out[i].C += in[i].I * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) + ((double)180 / 360 * Math.PI * 2));
     out[i].C += in[i].Q * Math.sin((i * ntsc_color_subcarrier_frequency / dot_clock_frequency * Math.PI * 2) + ((double)90 / 360 * Math.PI * 2));
     */
  }

  double[] filter_in = new double[in.length];
  for (int i = 0; i < in.length; i++) {
    filter_in[i] = out[i].Y;
  }
  //filter_in = notch_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 1.5);//Y-TRAP

  filter_in = low_pass_filter(filter_in, dot_clock_frequency, ntsc_bandwidth_limiting, 0.8 / Math.sqrt(2));
  //filter_in = low_pass_filter(filter_in, dot_clock_frequency, 4.2 * 1000 * 1000 * 1.2, 1 / Math.sqrt(2));
  //filter_in = notch_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 1);

  double[] y_trap = {//ボケるから使わないほうがいい
  /*
フィルタ長 : N = 31
   フィルタの種類 : BEF
   窓の種類 : Hann窓
   正規化低域遮断周波数 : 0.2
   正規化高域遮断周波数 : 0.3
   */
    0.000000000000000e+00, 
    -4.725279957023809e-04, 
    1.424759880206008e-18, 
    2.977709252466368e-03, 
    -2.295867618526002e-18, 
    1.949085916259688e-18, 
    -4.794657765435172e-18, 
    -2.094260066377138e-02, 
    1.532841164091988e-17, 
    6.604660330585446e-02, 
    -2.923628874389532e-17, 
    -1.263242656484571e-01, 
    3.138144248583225e-17, 
    1.790101269667080e-01, 
    0.000000000000000e+00, 
    7.999999999999999e-01, 
    0.000000000000000e+00, 
    1.790101269667080e-01, 
    3.138144248583225e-17, 
    -1.263242656484571e-01, 
    -2.923628874389532e-17, 
    6.604660330585446e-02, 
    1.532841164091988e-17, 
    -2.094260066377138e-02, 
    -4.794657765435172e-18, 
    1.949085916259688e-18, 
    -2.295867618526002e-18, 
    2.977709252466368e-03, 
    1.424759880206008e-18, 
    -4.725279957023809e-04, 
    0.000000000000000e+00, 
  };
  //filter_in = fir_filter(filter_in, y_trap);
  /*
  filter_in = notch_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 0.5);
   filter_in = notch_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 0.5);
   filter_in = notch_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 0.5);
   */
  for (int i = 0; i < in.length; i++) {
    out[i].Y = filter_in[i];
  }

  for (int i = 0; i < in.length; i++) {
    filter_in[i] = out[i].C;
  }

  /*
  double[] chroma_bandpass = {
   -4.242471930779368e-18, 1.614053693849225e-18, 6.519365368015782e-04, -1.070385191338824e-18, -1.243193145206730e-03, 6.572380488174118e-18, 1.545341331314938e-03, -1.180978157733511e-18, -1.219690279417950e-03, 3.155999509002607e-18, -1.308633300379172e-18, 6.438041361243076e-19, 2.015481444497646e-03, -1.269127297414911e-17, -4.150521278297991e-03, 1.798713606618301e-18, 5.226906703516515e-03, -1.905519005086401e-17, -4.024258869593409e-03, 0.000000000000000e+00, -3.101792343338087e-18, 9.597937852049863e-18, 6.064704797548081e-03, 4.183690829193989e-19, -1.190235456808759e-02, 4.547678784924444e-17, 1.435154478230210e-02, 5.183815941080771e-18, -1.065089255751572e-02, 1.929837352009974e-17, -5.318258814903765e-18, -4.922016226780956e-18, 1.529750482053906e-02, -6.473767323297273e-17, -2.976146660162287e-02, 3.159005230026598e-17, 3.603425196620000e-02, -2.817701229600306e-17, -2.729525630881510e-02, 1.241279428794238e-17, -7.111417857862676e-18, 1.288401115977121e-17, 4.411304735764224e-02, -2.654044884238175e-17, -9.765054582794508e-02, 3.810408382120118e-17, 1.491778522165045e-01, -3.441178367727382e-17, -1.864192084151082e-01, 0.000000000000000e+00, 2.000000000000000e-01, 0.000000000000000e+00, -1.864192084151082e-01, -3.441178367727382e-17, 1.491778522165045e-01, 3.810408382120118e-17, -9.765054582794508e-02, -2.654044884238175e-17, 4.411304735764224e-02, 1.288401115977121e-17, -7.111417857862676e-18, 1.241279428794238e-17, -2.729525630881510e-02, -2.817701229600306e-17, 3.603425196620000e-02, 3.159005230026598e-17, -2.976146660162287e-02, -6.473767323297273e-17, 1.529750482053906e-02, -4.922016226780956e-18, -5.318258814903765e-18, 1.929837352009974e-17, -1.065089255751572e-02, 5.183815941080771e-18, 1.435154478230210e-02, 4.547678784924444e-17, -1.190235456808759e-02, 4.183690829193989e-19, 6.064704797548081e-03, 9.597937852049863e-18, -3.101792343338087e-18, 0.000000000000000e+00, -4.024258869593409e-03, -1.905519005086401e-17, 5.226906703516515e-03, 1.798713606618301e-18, -4.150521278297991e-03, -1.269127297414911e-17, 2.015481444497646e-03, 6.438041361243076e-19, -1.308633300379172e-18, 3.155999509002607e-18, -1.219690279417950e-03, -1.180978157733511e-18, 1.545341331314938e-03, 6.572380488174118e-18, -1.243193145206730e-03, -1.070385191338824e-18, 6.519365368015782e-04, 1.614053693849225e-18, -4.242471930779368e-18, 
   };
   */
  double[] chroma_bandpass = {
  /*
フィルタ長 : N = 35
   フィルタの種類 : BPF
   窓の種類 : Hamming
   正規化低域遮断周波数 : 0.125714 (1.8 MHz)
   正規化高域遮断周波数 : 0.307302 (4.4 MHz)
   */
    3.413715564813507e-04, 
    -9.974292543167959e-04, 
    5.376670544883840e-05, 
    6.583580097283970e-03, 
    3.503585373224369e-03, 
    -6.067055578517022e-03, 
    1.134559956263701e-04, 
    -7.330640931822142e-03, 
    -3.044713089360271e-02, 
    5.154872193996149e-03, 
    4.534889777994558e-02, 
    6.655500371526442e-03, 
    2.577315259029779e-02, 
    7.068352812775164e-02, 
    -1.154641757335201e-01, 
    -2.558984719798458e-01, 
    7.125179316017957e-02, 
    3.631760000000001e-01, 
    7.125179316017957e-02, 
    -2.558984719798458e-01, 
    -1.154641757335201e-01, 
    7.068352812775164e-02, 
    2.577315259029779e-02, 
    6.655500371526442e-03, 
    4.534889777994558e-02, 
    5.154872193996149e-03, 
    -3.044713089360271e-02, 
    -7.330640931822142e-03, 
    1.134559956263701e-04, 
    -6.067055578517022e-03, 
    3.503585373224369e-03, 
    6.583580097283970e-03, 
    5.376670544883840e-05, 
    -9.974292543167959e-04, 
    3.413715564813507e-04, 
  };
  filter_in = fir_filter(filter_in, chroma_bandpass);
  //filter_in = band_pass_filter(filter_in, dot_clock_frequency, ntsc_color_subcarrier_frequency, 0.3);
  //filter_in = low_pass_filter(filter_in, dot_clock_frequency, ntsc_bandwidth_limiting, 1 / Math.sqrt(3));
  for (int i = 0; i < in.length; i++) {
    out[i].C = filter_in[i];
  }

  for (int i = 0; i < in.length; i++) {
    out[i].composite = out[i].Y + out[i].C + in[i].composite;
  }
  return out;
}
