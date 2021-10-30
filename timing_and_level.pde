double ntsc_color_subcarrier_frequency = 3579545;

double ntsc_Y_sampling_frequency = 13500000;//無視 これでサンプリングすると横の画素数が720になる
double ntsc_chroma_sampling_frequency = 6750000;//無視

double ntsc_bandwidth_limiting = 4.2 * 1000 * 1000;
//double ntsc_bandwidth_limiting = 5.6 * 1000 * 1000;

double ntsc_horizontal_frequency = ntsc_color_subcarrier_frequency / 227.5;
double ntsc_horizontal_end = (1 / ntsc_horizontal_frequency);
double ntsc_horizontal_number_of_color_cycle = 227.5;

double ntsc_vertical_field_number_of_line = 262.5;
double ntsc_vertical_frame_number_of_line = ntsc_vertical_field_number_of_line * 2;

double ntsc_vertical_frequency = ntsc_horizontal_frequency / ntsc_vertical_field_number_of_line;

double ntsc_horizontal_sync_pulse_start = 0 / 1000 / 1000;
double ntsc_horizontal_sync_pulse_end = 4.7 / 1000 / 1000;
double ntsc_horizontal_back_porch = 4.5 / 1000 / 1000;
double ntsc_horizontal_front_porch = 1.5 / 1000 / 1000;

double ntsc_horizontal_equalizing_sync_pulse_start = 0;
double ntsc_horizontal_equalizing_sync_pulse_end = 2.3 / 1000 / 1000;

double ntsc_horizontal_serrated_sync_pulse_start = 0 / 1000 / 1000;
double ntsc_horizontal_serrated_sync_pulse_end = (ntsc_horizontal_end / 2) - (4.7 / 1000 / 1000);

double ntsc_horizontal_view_start = ntsc_horizontal_sync_pulse_end + ntsc_horizontal_back_porch;
double ntsc_horizontal_view_end = (1 / ntsc_horizontal_frequency) - ntsc_horizontal_front_porch;

double ntsc_horizontal_view_edge = 0.28 / 1000 / 1000;

double ntsc_horizontal_color_burst_start = 1 / ntsc_color_subcarrier_frequency * 19;
double ntsc_horizontal_color_burst_end = 1 / ntsc_color_subcarrier_frequency * (19 + 9);

double ntsc_vertical_equalizing_sync_start_line = 0;
double ntsc_vertical_equalizing_sync_end_line = 8;

double ntsc_vertical_sync_start_line = 3;
double ntsc_vertical_sync_end_line = 5;

double ntsc_vertical_view_start = 20;
double ntsc_vertical_view_end = ntsc_vertical_field_number_of_line + 1;


double dot_clock_frequency = ntsc_color_subcarrier_frequency * 4;
//double dot_clock_frequency = ntsc_color_subcarrier_frequency * 12;

/*
ntsc horizontal line
 sync_pulse,back_porch,video,front_porch
 */

double ntsc_IRE = 1.0 / 140;

double ntsc_sync_level = (double)-40 * ntsc_IRE;//Volt
double ntsc_luminance_level = (double)100 * ntsc_IRE;//Volt max
double ntsc_color_burst_level = (double)40 * ntsc_IRE;//Volt peak to peak
