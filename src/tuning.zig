const do_tuning = false;

pub const tunable_constants = if (do_tuning) struct {
    pub var rfp_multiplier: i16 = 150;
    pub var quiesce_see_pruning_threshold: i16 = -100;

    pub var see_quiet_pruning_multiplier: i16 = -80;
    pub var see_noisy_pruning_multiplier: i16 = -40;

    pub var lmr_mult: u8 = 8;
    pub var lmr_base: u8 = 128;
} else struct {
    pub const rfp_multiplier: i16 = 150;

    pub const quiesce_see_pruning_threshold: i16 = -100;
    pub const see_quiet_pruning_multiplier: i16 = -80;
    pub const see_noisy_pruning_multiplier: i16 = -40;

    pub const lmr_mult: u8 = 8;
    pub const lmr_base: u8 = 128;
};
