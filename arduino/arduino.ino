/** 
 * Arduino sensor pack, used to trigger sounds in ToyBox.
 *
 * VCNL4000/proximity sensor code by: Jim Lindblom, SparkFun Electronics
 * I2C code dependent on: http://www.i2cdevlib.com/usage
 *   in ~/Documents/Arduino/Libraries, symlink in the i2cdevlib checkout:
 *     * ln -s <your source dir>/i2cdevlib/Arduino/I2Cdev i2cdev
 *     * ln -s <your source dir>/i2cdevlib/Arduino/MPU6050 mpu6050
 */
#include "Wire.h"
#include "I2Cdev.h"
#include "MPU6050_6Axis_MotionApps20.h"

// general constants, tune these
#define BAUD_RATE 9600
#define BUTTON_DELAY 100
#define MICROPHONE_DISABLED
#define MICROPHONE_THRESHOLD 860
#define MICROPHONE_DELAY 500
#define PROXIMITY_DISABLED
#define PROXIMITY_THRESHOLD 10
#define PROXIMITY_DELAY 100
//#define ACCELEROMETER_DISABLED
#define ACCELEROMETER_THRESHOLD 9000
#define ACCELEROMETER_DELAY 500
//#define GYROSCOPE_DISABLED
#define GYROSCOPE_THRESHOLD 20
#define GYROSCOPE_DELAY 100

// proximity sensor VCNL4000
#define VCNL4000_ADDRESS 0x13  // 0x26 write, 0x27 read
#define COMMAND_0 0x80  // starts measurments, relays data ready info
#define PRODUCT_ID 0x81  // product ID/revision ID, should read 0x11
#define IR_CURRENT 0x83  // sets IR current in steps of 10mA 0-200mA
#define PROXIMITY_RESULT_MSB 0x87  // High byte of proximity measure
#define PROXIMITY_RESULT_LSB 0x88  // low byte of proximity measure
#define PROXIMITY_FREQ 0x89  // Proximity IR test signal freq, 0-3
#define PROXIMITY_MOD 0x8A  // proximity modulator timing

// class default I2C address is 0x68
// specific I2C addresses may be passed as a parameter here
// AD0 low = 0x68 (default for SparkFun breakout and InvenSense evaluation board)
// AD0 high = 0x69
MPU6050 mpu;

// digital pins
const int button1Pin = 8;
const int button2Pin = 7;
const int button3Pin = 4;
const int triggerLedPin = 12;
const int hardwareLedPin = 13;

// analog pins
const int microphonePin = 1;

// states
boolean hardwareLedState = false;
int button1State = 0;
int button2State = 0;
int button3State = 0;
int microphoneState = 0;
int accelerometerState = 0;
int gyroscopePitchState = 0;
int gyroscopeRollState = 0;

// prximity sensor
int proximityValueInit;

// MPU
unsigned int initialized = 0;
bool dmpReady = false;  // set true if DMP init was successful
uint8_t mpuIntStatus;   // holds actual interrupt status byte from MPU
uint8_t devStatus;      // return status after each device operation (0 = success, !0 = error)
uint16_t packetSize;    // expected DMP packet size (default is 42 bytes)
uint16_t fifoCount;     // count of all bytes currently in FIFO
uint8_t fifoBuffer[64]; // FIFO storage buffer

// orientation/motion vars
Quaternion q;           // [w, x, y, z]         quaternion container
VectorInt16 aa;         // [x, y, z]            accel sensor measurements
VectorInt16 aaReal;     // [x, y, z]            gravity-free accel sensor measurements
VectorInt16 aaWorld;    // [x, y, z]            world-frame accel sensor measurements
VectorFloat gravity;    // [x, y, z]            gravity vector
float ypr[3];           // [yaw, pitch, roll]   yaw/pitch/roll container and gravity vector

/**
 * Arduino initialization.
 */
void setup() {

  // initialize I2C and serial connection
  Wire.begin();
  Serial.begin(BAUD_RATE);
  analogReference(EXTERNAL);

  // LEDs
  pinMode(hardwareLedPin, OUTPUT);
  pinMode(triggerLedPin, OUTPUT);
  digitalWrite(triggerLedPin, LOW);

  // buttons
  pinMode(button1Pin, INPUT);
  pinMode(button2Pin, INPUT);
  pinMode(button3Pin, INPUT);
  
  // microphone
  pinMode(microphonePin, INPUT);
  
  // proximity
  setupProximity();
  
  // MPU
  setupMPU();

  Serial.println("ready");
}

void setupProximity() {

  #ifdef PROXIMITY_DISABLED
  return;
  #endif
  
  // test that the device is working correctly
  byte vcnl4000ProductId = readByte(PRODUCT_ID);

  // product ID should be 0x11
  if (vcnl4000ProductId != 0x11)  {
    Serial.print("error: VNCL4000 error, not reading correct product ID: 0x11 != ");
    Serial.println(vcnl4000ProductId, HEX);
  } else {
    delay(100);
  }

  writeByte(IR_CURRENT, 20);  // Set IR current to 200mA
  writeByte(PROXIMITY_FREQ, 2);  // 781.25 kHz
  writeByte(PROXIMITY_MOD, 0x81);  // 129, recommended by Vishay
  
  // initialize
  proximityValueInit = readProximity(false);
}

/**
 * DMP interrupt handling.
 */
volatile bool mpuInterrupt = false;     // indicates whether MPU interrupt pin has gone high
void dmpDataReady() {
  mpuInterrupt = true;
}

void setupMPU() {
  
  mpu.initialize();
  devStatus = mpu.dmpInitialize();
  
  // make sure it worked (returns 0 if so)
  if (devStatus == 0) {

    // turn on the DMP, now that it's ready
    mpu.setDMPEnabled(true);

    // enable Arduino interrupt detection
    attachInterrupt(0, dmpDataReady, RISING);
    mpuIntStatus = mpu.getIntStatus();

    // set our DMP Ready flag so the main loop() function knows it's okay to use it
    dmpReady = true;

    // get expected DMP packet size for later comparison
    packetSize = mpu.dmpGetFIFOPacketSize();
  } else {
    // ERROR!
    // 1 = initial memory load failed
    // 2 = DMP configuration updates failed
    // (if it's going to break, usually the code will be 1)
    Serial.print(F("error: MPU DMP Initialization failed (code "));
    Serial.print(devStatus);
    Serial.println(F(")"));
  }
}

/**
 * Main event loop.
 */
void loop() {

  blinkHardwareLed();
  
  // wait for MPU interrupt or extra packet(s) available
  while (!mpuInterrupt && fifoCount < packetSize) {}

  button1State = checkButtonState(button1Pin, button1State, "1");
  button2State = checkButtonState(button2Pin, button2State, "2");
  button3State = checkButtonState(button3Pin, button3State, "3");
  checkMicrophoneState();
  proximitySensorCheck();

  // if MPU DMP programming failed, give up now
  if (!dmpReady) return;

  checkMPU();
}

int checkButtonState(int buttonPin, int buttonState, String buttonName) {
  int value = digitalRead(buttonPin);

  if (value != buttonState) {
    digitalStateChange(value, "button" + buttonName, BUTTON_DELAY);
  }
  
  return value;
}

void checkMicrophoneState() {
  
  #ifdef MICROPHONE_DISABLED
  return;
  #endif
  
  int value = analogRead(microphonePin);

  if (value > MICROPHONE_THRESHOLD && microphoneState == 0) {
    Serial.println(value);
    digitalStateChange(1, "microphone", MICROPHONE_DELAY);
    microphoneState = 1;
  } else if (value < MICROPHONE_THRESHOLD && microphoneState == 1) {
    digitalStateChange(0, "microphone", MICROPHONE_DELAY);
    microphoneState = 0;    
  }
}

void proximitySensorCheck() {
  
  #ifdef PROXIMITY_DISABLED
  return;
  #endif
  
  int value = readProximity(true);

  if (value > PROXIMITY_THRESHOLD) {
    Serial.print("proximity:");
    Serial.println(value, DEC);
    analogWrite(triggerLedPin, HIGH);
    delay(PROXIMITY_DELAY); // required else it loops too fast
    analogWrite(triggerLedPin, LOW);
  }
}

void checkMPU() {
  
   // reset interrupt flag and get INT_STATUS byte
  mpuInterrupt = false;
  mpuIntStatus = mpu.getIntStatus();

  // get current FIFO count
  fifoCount = mpu.getFIFOCount();

  // check for overflow (this should never happen unless our code is too inefficient)
  if ((mpuIntStatus & 0x10) || fifoCount == 1024) {
      // reset so we can continue cleanly
      mpu.resetFIFO();
      // Serial.println(F("FIFO overflow!"));

  // otherwise, check for DMP data ready interrupt (this should happen frequently)
  } else if (mpuIntStatus & 0x02) {

    // wait for correct available data length, should be a VERY short wait
    while (fifoCount < packetSize) fifoCount = mpu.getFIFOCount();

    // read a packet from FIFO
    mpu.getFIFOBytes(fifoBuffer, packetSize);
    
    // track FIFO count here in case there is > 1 packet available
    // (this lets us immediately read more without waiting for an interrupt)
    fifoCount -= packetSize;

    checkAccelerometer();
    checkGyroscope();
  }

}

void checkAccelerometer() {
  
  #ifdef ACCELEROMETER_DISABLED
  return;
  #endif
  
  if (initialized < 100) {
    // initialize aaReal
    mpu.dmpGetQuaternion(&q, fifoBuffer);
    mpu.dmpGetAccel(&aaReal, fifoBuffer);
    initialized++;

    return;
  }

  // get current values
  mpu.dmpGetQuaternion(&q, fifoBuffer);
  mpu.dmpGetAccel(&aaWorld, fifoBuffer);

  int normX = aaWorld.x - aaReal.x;
  int normY = aaWorld.y - aaReal.y;
  int normZ = aaWorld.z - aaReal.z;

  if (overAccelThreshold(normX, normY, normZ) && accelerometerState == 0) {
    digitalStateChange(HIGH, "accelerometer", ACCELEROMETER_DELAY);
    accelerometerState = 1;
  } else if (!overAccelThreshold(normX, normY, normZ) && accelerometerState == 1) {
    digitalStateChange(LOW, "accelerometer", ACCELEROMETER_DELAY);
    accelerometerState = 0;
  }
}

boolean overAccelThreshold(int normX, int normY, int normZ) {

 return (normX > ACCELEROMETER_THRESHOLD ||
         normY > ACCELEROMETER_THRESHOLD||
         normZ > ACCELEROMETER_THRESHOLD ||
         normX < -1 * ACCELEROMETER_THRESHOLD ||
         normY < -1 * ACCELEROMETER_THRESHOLD||
         normZ < -1 * ACCELEROMETER_THRESHOLD);
}

void checkGyroscope() {

  #ifdef GYROSCOPE_DISABLED
  return;
  #endif
  
  // get current values
  mpu.dmpGetQuaternion(&q, fifoBuffer);
  mpu.dmpGetGravity(&gravity, &q);
  mpu.dmpGetYawPitchRoll(ypr, &q, &gravity);

  int pitch = (ypr[2] * 180/M_PI);
  int roll = (ypr[1] * 180/M_PI);
  boolean stateChange = false;

  if (isOverGyroscopeThreshold(pitch) && gyroscopePitchState == 0) {
    digitalStateChangeNoDelay(HIGH, "gyro:pitch");
    gyroscopePitchState = 1;
    stateChange = true;
  } else if (!isOverGyroscopeThreshold(pitch) && gyroscopePitchState == 1) {
    digitalStateChangeNoDelay(LOW, "gyro:pitch");
    gyroscopePitchState = 0;
    stateChange = true;
  }

  if (isOverGyroscopeThreshold(roll) && gyroscopeRollState == 0) {
    digitalStateChangeNoDelay(HIGH, "gyro:roll");
    gyroscopeRollState = 1;
    stateChange = true;
  } else if (!isOverGyroscopeThreshold(roll) && gyroscopeRollState == 1) {
    digitalStateChangeNoDelay(LOW, "gyro:roll");
    gyroscopeRollState = 0;
    stateChange = true;
  }

  if (stateChange) {
    delay(GYROSCOPE_DELAY);
  }
}

boolean isOverGyroscopeThreshold(int value) {
  return (value > GYROSCOPE_THRESHOLD || value < -1 * GYROSCOPE_THRESHOLD);
}

void blinkHardwareLed() {
  hardwareLedState = !hardwareLedState;
  digitalWrite(hardwareLedPin, hardwareLedState);
}

/**
 * A digital (high/low) state change of some sensor. This will cause a change in a companion LED
 * and write the state change to the serial output.
 */
void digitalStateChangeNoDelay(int digitalValue, String serialName) {

  if (digitalValue == HIGH) {
    digitalWrite(triggerLedPin, HIGH);
    Serial.println(serialName + ":on");
  } else {
    digitalWrite(triggerLedPin, LOW);
    Serial.println(serialName + ":off");
  }
}

void digitalStateChange(int digitalValue, String serialName, int delayMillis) {
  
  digitalStateChangeNoDelay(digitalValue, serialName);
  delay(delayMillis);
}

// returns a value between 0-100 where 100 is closest (capped at some distance)
int readProximity(boolean limit) {
  int data;
  byte temp;
  
  temp = readByte(COMMAND_0);
  writeByte(COMMAND_0, temp | 0x08);  // command the sensor to perform a proximity measure
  
  while(!(readByte(COMMAND_0)&0x20)) 
    ;  // Wait for the proximity data ready bit to be set
  data = readByte(PROXIMITY_RESULT_MSB) << 8;
  data |= readByte(PROXIMITY_RESULT_LSB);
  
  if (!limit) {
    return data; // on startup

  } else {
    int normValue = data - proximityValueInit;

    if (normValue < 0) {
      return 0;
    } else if (normValue > 1000) {
      return 100;
    } else {
      return normValue / 10;
    }
  }
}

/**
 * Writes a single byte of data to address.
 * Used by proximity sensor.
 */
void writeByte(byte address, byte data) {
  Wire.beginTransmission(VCNL4000_ADDRESS);
  Wire.write(address);
  Wire.write(data);
  Wire.endTransmission();
}

/**
 * Reads a single byte of data from address.
 * Used by proximity sensor.
 */
byte readByte(byte address) {

  Wire.beginTransmission(VCNL4000_ADDRESS);
  Wire.write(address);
  Wire.endTransmission();

  Wire.requestFrom(VCNL4000_ADDRESS, 1);
  while(!Wire.available()) {}
  return Wire.read();
}

