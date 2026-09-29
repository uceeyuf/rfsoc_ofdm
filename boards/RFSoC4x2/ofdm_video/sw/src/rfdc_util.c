/*
 * RF data converter bring-up for DAC_B (tile 228 = DAC tile 0, block 0) and
 * ADC_B (tile 226 = ADC tile 2, block 0). Startup flow follows the Xilinx
 * zcu208 dds_ila example.
 * Copyright (c) 2026, Yijie Yu. BSD-3-Clause.
 */

#include <stdio.h>
#include <stdarg.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "sleep.h"
#include "xrfdc.h"
#include <metal/log.h>
#include <metal/sys.h>
#include "rfdc_util.h"

static XRFdc rfdc;

static void rfdc_log_handler(enum metal_log_level level, const char *format, ...)
{
    char msg[256];
    va_list args;
    va_start(args, format);
    vsnprintf(msg, sizeof(msg), format, args);
    va_end(args);
    if (level <= METAL_LOG_WARNING)
        xil_printf("metal: %s\r", msg);
}

int rfdc_init(void)
{
    struct metal_init_params init_param = METAL_INIT_DEFAULTS;
    init_param.log_handler = rfdc_log_handler;
    if (metal_init(&init_param)) {
        xil_printf("libmetal init failed\r\n");
        return -1;
    }

    XRFdc_Config *cfg = XRFdc_LookupConfig(XPAR_XRFDC_0_DEVICE_ID);
    if (!cfg || XRFdc_CfgInitialize(&rfdc, cfg) != XRFDC_SUCCESS) {
        xil_printf("RFDC init failed\r\n");
        return -1;
    }

    XRFdc_StartUp(&rfdc, XRFDC_DAC_TILE, DAC_TILE);
    XRFdc_StartUp(&rfdc, XRFDC_ADC_TILE, ADC_TILE);
    usleep(200000);

    XRFdc_IPStatus st;
    u32 dac_lock = 0, adc_lock = 0;
    XRFdc_GetIPStatus(&rfdc, &st);
    XRFdc_GetPLLLockStatus(&rfdc, XRFDC_DAC_TILE, DAC_TILE, &dac_lock);
    XRFdc_GetPLLLockStatus(&rfdc, XRFDC_ADC_TILE, ADC_TILE, &adc_lock);
    xil_printf("DAC tile 228 state 0x%x PLL %s | ADC tile 226 state 0x%x PLL %s\r\n",
               st.DACTileStatus[DAC_TILE].TileState, dac_lock == XRFDC_PLL_LOCKED ? "locked" : "UNLOCKED",
               st.ADCTileStatus[ADC_TILE].TileState, adc_lock == XRFDC_PLL_LOCKED ? "locked" : "UNLOCKED");

    if (st.DACTileStatus[DAC_TILE].TileState != 0xF || st.ADCTileStatus[ADC_TILE].TileState != 0xF)
        return -1;
    return 0;
}

int rfdc_set_carrier(int mhz)
{
    XRFdc_Mixer_Settings m;
    u32 s;

    m.Freq = mhz;
    m.PhaseOffset = 0.0;
    m.EventSource = XRFDC_EVNT_SRC_TILE;
    m.CoarseMixFreq = XRFDC_COARSE_MIX_BYPASS;
    m.MixerMode = XRFDC_MIXER_MODE_C2R;
    m.FineMixerScale = XRFDC_MIXER_SCALE_1P0;
    m.MixerType = XRFDC_MIXER_TYPE_FINE;
    s  = XRFdc_SetMixerSettings(&rfdc, XRFDC_DAC_TILE, DAC_TILE, DAC_BLOCK, &m);
    s |= XRFdc_UpdateEvent(&rfdc, XRFDC_DAC_TILE, DAC_TILE, DAC_BLOCK, XRFDC_EVENT_MIXER);

    m.Freq = -mhz;
    m.MixerMode = XRFDC_MIXER_MODE_R2C;
    s |= XRFdc_SetMixerSettings(&rfdc, XRFDC_ADC_TILE, ADC_TILE, ADC_BLOCK, &m);
    s |= XRFdc_UpdateEvent(&rfdc, XRFDC_ADC_TILE, ADC_TILE, ADC_BLOCK, XRFDC_EVENT_MIXER);

    xil_printf("carrier %d MHz %s\r\n", mhz, s == XRFDC_SUCCESS ? "" : "(mixer update FAILED)");
    return s == XRFDC_SUCCESS ? 0 : -1;
}
