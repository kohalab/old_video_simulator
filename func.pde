
import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

FileOutputStream fos;

double[] double_float64_read(String path) {
  try {
    FileInputStream fis = new FileInputStream(new File(path));
    BufferedInputStream reader = new BufferedInputStream(fis);
    //println(((double)reader.available() / 1024)+"KB");

    byte[] bytes = new byte[8];
    double[] out = new double[reader.available() / bytes.length];

    int i = 0;

    while (reader.read(bytes, 0, bytes.length) != -1) {
      //println(bytes);
      ByteBuffer buf = ByteBuffer.wrap(bytes);
      buf.order(ByteOrder.LITTLE_ENDIAN);
      out[i] = buf.getDouble();
      i++;
    }
    return out;
  }
  catch(IOException e) {
    println(e);
    return null;
  }
}

void double_float64_write(String path, double[] in) {
  try {
    fos = new FileOutputStream(new File(path));
  } 
  catch(IOException e) {
    println(e);
    return;
  }

  try {
    int arraySize = Double.SIZE / Byte.SIZE;
    ByteBuffer buffer = ByteBuffer.allocate(arraySize);
    buffer.order(ByteOrder.LITTLE_ENDIAN);
    for (int i = 0; i < in.length; i++) {
      //float64で保存
      fos.write(buffer.putDouble(in[i]).array());
      buffer.clear();
    }
    fos.flush();//毎回呼ぶと遅い
  }
  catch(IOException e) {
    println(e);
    return;
  }
}

void double_boolean_write(String path, boolean[] in) {
  try {
    fos = new FileOutputStream(new File(path));
  } 
  catch(IOException e) {
    println(e);
    return;
  }

  try {
    for (int i = 0; i < in.length; i++) {
      //signed charで保存
      fos.write(in[i] ? 127 : -128);
    }
    fos.flush();//毎回呼ぶと遅い
  }
  catch(IOException e) {
    println(e);
    return;
  }
}


import com.sun.image.codec.jpeg.*;
import java.io.ByteArrayOutputStream;
import java.io.FileNotFoundException;

public void mysave(String filename, PImage img_in) { 
  java.awt.image.BufferedImage img=new java.awt.image.BufferedImage(img_in.width, img_in.height, 
    java.awt.image.BufferedImage.TYPE_INT_RGB); 
  img_in.loadPixels(); 
  img.setRGB(0, 0, img_in.width, img_in.height, img_in.pixels, 0, img_in.width); 

  String extn=filename.substring(filename.lastIndexOf('.')+1).toLowerCase(); 
  if (extn.equals("jpg")) {

    try {
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      JPEGImageEncoder encoder = JPEGCodec.createJPEGEncoder(out);
      JPEGEncodeParam p = encoder.getDefaultJPEGEncodeParam(img);
      p.setQuality(0.95, true);
      p.setVerticalSubsampling(1, 1);
      p.setVerticalSubsampling(2, 1);
      encoder.setJPEGEncodeParam(p);
      encoder.encode(img);

      File file = new File(savePath(filename));
      FileOutputStream fo = new FileOutputStream(file);
      out.writeTo(fo);
      println("saved "+filename);
    }
    catch(FileNotFoundException e) {
      System.out.println(e);
    }
    catch(IOException ioe) {
      System.out.println(ioe);
    }
  } else if (extn.equals("png")) { // add here as needed 

    try { 
      javax.imageio.ImageIO.write(img, extn, new File(savePath(filename))); 
      println("saved "+filename);
    } 
    catch(Exception e) { 
      System.err.println("error while saving as "+extn); 
      e.printStackTrace();
    }
  } else { 
    super.save(filename);
  }
}
