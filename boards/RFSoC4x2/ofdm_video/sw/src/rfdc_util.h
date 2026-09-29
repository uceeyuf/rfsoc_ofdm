/*
 * RF data converter bring-up for the RFSoC4x2 DAC_B / ADC_B loop.
 * Copyright (c) 2026, Yijie Yu. BSD-3-Clause.
 */

#ifndef RFDC_UTIL_H_
#define RFDC_UTIL_H_

#define DAC_TILE    0       /* DAC tile 228 */
#define DAC_BLOCK   0       /* DAC_B = ch0 */
#define ADC_TILE    2       /* ADC tile 226 */
#define ADC_BLOCK   0       /* ADC_B = ch0 */

int rfdc_init(void);
int rfdc_set_carrier(int mhz);

#endif
