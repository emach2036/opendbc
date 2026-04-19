#pragma once

#include "opendbc/safety/declarations.h"

// CAN msgs we care about
#define MAZDA_LKAS          0x243U
#define MAZDA_LKAS_HUD      0x440U
#define MAZDA_CRZ_CTRL      0x21cU
#define MAZDA_CRZ_BTNS      0x09dU
#define MAZDA_STEER_TORQUE  0x240U
#define MAZDA_ENGINE_DATA   0x202U
#define MAZDA_PEDALS        0x165U

// CAN bus numbers (Panda firmware: physical buses 0, 1, 2 only).
#define MAZDA_MAIN 0
#define MAZDA_CAM  2
// PEDALS (0x165) on PT (0) or forwarded on camera bus (2). Logs/cereal may show src 130 (= 2 + 128 relay offset).
#define MAZDA_PEDALS_BUS_ALT 2U

// Vision-Only / no MRCC: engage with steering-wheel buttons (CRZ_BTNS), not CRZ_ACTIVE on bus.
static bool mazda_prev_res = false;
static bool mazda_prev_set_m = false;
static bool mazda_prev_cancel = false;

// track msgs coming from OP so that we know what CAM msgs to drop and what to forward
static void mazda_rx_hook(const CANPacket_t *msg) {
  if ((int)msg->bus == MAZDA_MAIN) {
    if (msg->addr == MAZDA_ENGINE_DATA) {
      // sample speed: scale by 0.01 to get kph
      int speed = (msg->data[2] << 8) | msg->data[3];
      vehicle_moving = speed > 10; // moving when speed > 0.1 kph
    }

    if (msg->addr == MAZDA_STEER_TORQUE) {
      int torque_driver_new = msg->data[0] - 127U;
      // update array of samples
      update_sample(&torque_driver, torque_driver_new);
    }

    // DBC: RES @ bit 2, SET_M @ bit 5, CAN_OFF (cancel) @ bit 0 of CRZ_BTNS byte 0.
    if (msg->addr == MAZDA_CRZ_BTNS) {
      const bool res = GET_BIT(msg, 2U);
      const bool set_m = GET_BIT(msg, 5U);
      const bool cancel_btn = GET_BIT(msg, 0U);

      const bool res_rise = res && !mazda_prev_res;
      const bool set_rise = set_m && !mazda_prev_set_m;
      const bool cancel_rise = cancel_btn && !mazda_prev_cancel;

      if (res_rise || set_rise) {
        controls_allowed = true;
      }
      if (cancel_rise) {
        controls_allowed = false;
      }

      mazda_prev_res = res;
      mazda_prev_set_m = set_m;
      mazda_prev_cancel = cancel_btn;
    }

    if (msg->addr == MAZDA_ENGINE_DATA) {
      gas_pressed = (msg->data[4] || (msg->data[5] & 0xF0U));
    }
  }

  // PEDALS: same ID on PT bus or alternate forwarded bus (RxCheck accepts either; see mazda_rx_checks).
  if ((msg->addr == MAZDA_PEDALS) && (((int)msg->bus == MAZDA_MAIN) || ((unsigned int)msg->bus == MAZDA_PEDALS_BUS_ALT))) {
    brake_pressed = (msg->data[0] & 0x10U) != 0U;
  }
}

static bool mazda_tx_hook(const CANPacket_t *msg) {
  const TorqueSteeringLimits MAZDA_STEERING_LIMITS = {
    .max_torque = 800,
    .max_rate_up = 10,
    .max_rate_down = 25,
    .max_rt_delta = 300,
    .driver_torque_multiplier = 1,
    .driver_torque_allowance = 15,
    .type = TorqueDriverLimited,
  };

  bool tx = true;
  // Check if msg is sent on the main BUS
  if (msg->bus == (unsigned char)MAZDA_MAIN) {
    // steer cmd checks
    if (msg->addr == MAZDA_LKAS) {
      int desired_torque = (((msg->data[0] & 0x0FU) << 8) | msg->data[1]) - 2048U;

      if (steer_torque_cmd_checks(desired_torque, -1, MAZDA_STEERING_LIMITS)) {
        tx = false;
      }
    }

    // cruise buttons check
    if (msg->addr == MAZDA_CRZ_BTNS) {
      // allow resume spamming while controls allowed, but
      // only allow cancel while controls not allowed
      bool cancel_cmd = (msg->data[0] == 0x1U);
      if (!controls_allowed && !cancel_cmd) {
        tx = false;
      }
    }
  }

  return tx;
}

static safety_config mazda_init(uint16_t param) {
  static const CanMsg MAZDA_TX_MSGS[] = {{MAZDA_LKAS, 0, 8, .check_relay = true}, {MAZDA_CRZ_BTNS, 0, 8, .check_relay = false}, {MAZDA_LKAS_HUD, 0, 8, .check_relay = true}};

  static RxCheck mazda_rx_checks[] = {
    // CRZ_CTRL omitted: MRCC-less cars may not send it; engagement is via CRZ_BTNS + brake above.
    {.msg = {{MAZDA_CRZ_BTNS,     0, 8, 10U, .ignore_checksum = true, .ignore_counter = true, .ignore_quality_flag = true}, { 0 }, { 0 }}},
    {.msg = {{MAZDA_STEER_TORQUE, 0, 8, 83U, .ignore_checksum = true, .ignore_counter = true, .ignore_quality_flag = true}, { 0 }, { 0 }}},
    {.msg = {{MAZDA_ENGINE_DATA,  0, 8, 100U, .ignore_checksum = true, .ignore_counter = true, .ignore_quality_flag = true}, { 0 }, { 0 }}},
    {.msg = {
      {MAZDA_PEDALS, MAZDA_MAIN,         8, 50U, .ignore_checksum = true, .ignore_counter = true, .max_counter = 0U, .ignore_quality_flag = true},
      {MAZDA_PEDALS, MAZDA_PEDALS_BUS_ALT, 8, 50U, .ignore_checksum = true, .ignore_counter = true, .max_counter = 0U, .ignore_quality_flag = true},
      {0},
    }},
  };

  SAFETY_UNUSED(param);
  return BUILD_SAFETY_CFG(mazda_rx_checks, MAZDA_TX_MSGS);
}

const safety_hooks mazda_hooks = {
  .init = mazda_init,
  .rx = mazda_rx_hook,
  .tx = mazda_tx_hook,
};
