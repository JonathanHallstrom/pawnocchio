const std = @import("std");
const magics_generation = @import("magics_generation.zig");
const Square = @import("square.zig").Square;

const rook_array_size = 102400;
const bishop_array_size = 5248;
pub const total_array_size = rook_array_size + bishop_array_size;

pub const MagicEntry = struct {
    mask: u64,
    magic: u64,
    offs: u32,
    shift: u8,

    pub fn isMaskInverted() bool {
        return false;
    }

    pub inline fn getRookIndex(self: MagicEntry, occ: u64) u64 {
        return ((occ & self.mask) *% self.magic >> @intCast(self.shift)) + self.offs;
    }

    pub inline fn getBishopIndex(self: MagicEntry, occ: u64) u64 {
        return ((occ & self.mask) *% self.magic >> @intCast(self.shift)) + self.offs;
    }
};

pub const bishop_magics: [64]MagicEntry = .{
    .{ .mask = 18049651735527936, .magic = 571750359499009, .offs = 0, .shift = 58 },
    .{ .mask = 70506452091904, .magic = 2314869054803886088, .offs = 64, .shift = 59 },
    .{ .mask = 275415828992, .magic = 18297114782597248, .offs = 96, .shift = 59 },
    .{ .mask = 1075975168, .magic = 9513878405297209362, .offs = 128, .shift = 59 },
    .{ .mask = 38021120, .magic = 36594014867161088, .offs = 160, .shift = 59 },
    .{ .mask = 8657588224, .magic = 5068817390633216, .offs = 192, .shift = 59 },
    .{ .mask = 2216338399232, .magic = 1153423265497218, .offs = 224, .shift = 59 },
    .{ .mask = 567382630219776, .magic = 282576646309892, .offs = 256, .shift = 58 },
    .{ .mask = 9024825867763712, .magic = 1153123824548987136, .offs = 320, .shift = 59 },
    .{ .mask = 18049651735527424, .magic = 364800400405055554, .offs = 352, .shift = 59 },
    .{ .mask = 70506452221952, .magic = 9262220261195842061, .offs = 384, .shift = 59 },
    .{ .mask = 275449643008, .magic = 1482159399632896, .offs = 416, .shift = 59 },
    .{ .mask = 9733406720, .magic = 22592782644346880, .offs = 448, .shift = 59 },
    .{ .mask = 2216342585344, .magic = 648562945554907200, .offs = 480, .shift = 59 },
    .{ .mask = 567382630203392, .magic = 5226429569851984896, .offs = 512, .shift = 59 },
    .{ .mask = 1134765260406784, .magic = 4615209420687278592, .offs = 544, .shift = 59 },
    .{ .mask = 4512412933816832, .magic = 4612811957528167424, .offs = 576, .shift = 59 },
    .{ .mask = 9024825867633664, .magic = 844493716786192, .offs = 608, .shift = 59 },
    .{ .mask = 18049651768822272, .magic = 9225624940575981840, .offs = 640, .shift = 57 },
    .{ .mask = 70515108615168, .magic = 2324384828229634, .offs = 768, .shift = 57 },
    .{ .mask = 2491752130560, .magic = 3659209594394632, .offs = 896, .shift = 57 },
    .{ .mask = 567383701868544, .magic = 47358173439332609, .offs = 1024, .shift = 57 },
    .{ .mask = 1134765256220672, .magic = 144783693361203200, .offs = 1152, .shift = 59 },
    .{ .mask = 2269530512441344, .magic = 144150655950520856, .offs = 1184, .shift = 59 },
    .{ .mask = 2256206450263040, .magic = 6766414432076032, .offs = 1216, .shift = 59 },
    .{ .mask = 4512412900526080, .magic = 583251886984667417, .offs = 1248, .shift = 59 },
    .{ .mask = 9024834391117824, .magic = 288582494818862592, .offs = 1280, .shift = 57 },
    .{ .mask = 18051867805491712, .magic = 2605473671812350466, .offs = 1408, .shift = 55 },
    .{ .mask = 637888545440768, .magic = 11817586297181175872, .offs = 1920, .shift = 55 },
    .{ .mask = 1135039602493440, .magic = 6764470755942402, .offs = 2432, .shift = 57 },
    .{ .mask = 2269529440784384, .magic = 5206372844623235072, .offs = 2560, .shift = 59 },
    .{ .mask = 4539058881568768, .magic = 2882596231660724484, .offs = 2592, .shift = 59 },
    .{ .mask = 1128098963916800, .magic = 41661285854613504, .offs = 2624, .shift = 59 },
    .{ .mask = 2256197927833600, .magic = 180434565471547402, .offs = 2656, .shift = 59 },
    .{ .mask = 4514594912477184, .magic = 9224498076348317960, .offs = 2688, .shift = 57 },
    .{ .mask = 9592139778506752, .magic = 1460294380379701376, .offs = 2816, .shift = 55 },
    .{ .mask = 19184279556981248, .magic = 18017699469262912, .offs = 3328, .shift = 55 },
    .{ .mask = 2339762086609920, .magic = 145293866688581696, .offs = 3840, .shift = 57 },
    .{ .mask = 4538784537380864, .magic = 81628585059811842, .offs = 3968, .shift = 59 },
    .{ .mask = 9077569074761728, .magic = 721719715973580036, .offs = 4000, .shift = 59 },
    .{ .mask = 562958610993152, .magic = 9223936104609292289, .offs = 4032, .shift = 59 },
    .{ .mask = 1125917221986304, .magic = 282033611874336, .offs = 4064, .shift = 59 },
    .{ .mask = 2814792987328512, .magic = 11551471577334272, .offs = 4096, .shift = 57 },
    .{ .mask = 5629586008178688, .magic = 4899925328513990912, .offs = 4224, .shift = 57 },
    .{ .mask = 11259172008099840, .magic = 2305844117617251333, .offs = 4352, .shift = 57 },
    .{ .mask = 22518341868716544, .magic = 1153485008896532992, .offs = 4480, .shift = 57 },
    .{ .mask = 9007336962655232, .magic = 572403260392448, .offs = 4608, .shift = 59 },
    .{ .mask = 18014673925310464, .magic = 577657613798351360, .offs = 4640, .shift = 59 },
    .{ .mask = 2216338399232, .magic = 649090101112234016, .offs = 4672, .shift = 59 },
    .{ .mask = 4432676798464, .magic = 599388726756096, .offs = 4704, .shift = 59 },
    .{ .mask = 11064376819712, .magic = 83709198878753, .offs = 4736, .shift = 59 },
    .{ .mask = 22137335185408, .magic = 13528392175583248, .offs = 4768, .shift = 59 },
    .{ .mask = 44272556441600, .magic = 145390965195572240, .offs = 4800, .shift = 59 },
    .{ .mask = 87995357200384, .magic = 10525057602543566849, .offs = 4832, .shift = 59 },
    .{ .mask = 35253226045952, .magic = 289375036509685768, .offs = 4864, .shift = 59 },
    .{ .mask = 70506452091904, .magic = 6927103579393163904, .offs = 4896, .shift = 59 },
    .{ .mask = 567382630219776, .magic = 1152943497020973088, .offs = 4928, .shift = 58 },
    .{ .mask = 1134765260406784, .magic = 9386135493370446848, .offs = 4992, .shift = 59 },
    .{ .mask = 2832480465846272, .magic = 1197978392147005440, .offs = 5024, .shift = 59 },
    .{ .mask = 5667157807464448, .magic = 9223391830214313984, .offs = 5056, .shift = 59 },
    .{ .mask = 11333774449049600, .magic = 18015773973086464, .offs = 5088, .shift = 59 },
    .{ .mask = 22526811443298304, .magic = 4755801241006640164, .offs = 5120, .shift = 59 },
    .{ .mask = 9024825867763712, .magic = 4611723436199314432, .offs = 5152, .shift = 59 },
    .{ .mask = 18049651735527936, .magic = 9385647310953906304, .offs = 5184, .shift = 58 },
};
pub const rook_magics: [64]MagicEntry = .{
    .{ .mask = 282578800148862, .magic = 6953557963173269632, .offs = 0, .shift = 52 },
    .{ .mask = 565157600297596, .magic = 2323892592363716610, .offs = 4096, .shift = 53 },
    .{ .mask = 1130315200595066, .magic = 144124061482517536, .offs = 6144, .shift = 53 },
    .{ .mask = 2260630401190006, .magic = 2341876754303420416, .offs = 8192, .shift = 53 },
    .{ .mask = 4521260802379886, .magic = 2485991397857952384, .offs = 10240, .shift = 53 },
    .{ .mask = 9042521604759646, .magic = 144124001382305793, .offs = 12288, .shift = 53 },
    .{ .mask = 18085043209519166, .magic = 180146184134852736, .offs = 14336, .shift = 53 },
    .{ .mask = 36170086419038334, .magic = 144115465103606273, .offs = 16384, .shift = 52 },
    .{ .mask = 282578800180736, .magic = 2305983747247325192, .offs = 20480, .shift = 53 },
    .{ .mask = 565157600328704, .magic = 739997886644781318, .offs = 22528, .shift = 54 },
    .{ .mask = 1130315200625152, .magic = 10522801817132208128, .offs = 23552, .shift = 54 },
    .{ .mask = 2260630401218048, .magic = 140806208356480, .offs = 24576, .shift = 54 },
    .{ .mask = 4521260802403840, .magic = 91479801223184400, .offs = 25600, .shift = 54 },
    .{ .mask = 9042521604775424, .magic = 563018740531712, .offs = 26624, .shift = 54 },
    .{ .mask = 18085043209518592, .magic = 73746461094969384, .offs = 27648, .shift = 54 },
    .{ .mask = 36170086419037696, .magic = 14436429345171980544, .offs = 28672, .shift = 53 },
    .{ .mask = 282578808340736, .magic = 565149656170752, .offs = 30720, .shift = 53 },
    .{ .mask = 565157608292864, .magic = 1459166830099693696, .offs = 32768, .shift = 54 },
    .{ .mask = 1130315208328192, .magic = 9289774279966744, .offs = 33792, .shift = 54 },
    .{ .mask = 2260630408398848, .magic = 141287512606720, .offs = 34816, .shift = 54 },
    .{ .mask = 4521260808540160, .magic = 7881849179734656, .offs = 35840, .shift = 54 },
    .{ .mask = 9042521608822784, .magic = 324400460481954304, .offs = 36864, .shift = 54 },
    .{ .mask = 18085043209388032, .magic = 234328467900989696, .offs = 37888, .shift = 54 },
    .{ .mask = 36170086418907136, .magic = 9227877835572614241, .offs = 38912, .shift = 53 },
    .{ .mask = 282580897300736, .magic = 252202131038158849, .offs = 40960, .shift = 53 },
    .{ .mask = 565159647117824, .magic = 18031991771365440, .offs = 43008, .shift = 54 },
    .{ .mask = 1130317180306432, .magic = 1297054287024627712, .offs = 44032, .shift = 54 },
    .{ .mask = 2260632246683648, .magic = 15132668701625688128, .offs = 45056, .shift = 54 },
    .{ .mask = 4521262379438080, .magic = 9232423223017341057, .offs = 46080, .shift = 54 },
    .{ .mask = 9042522644946944, .magic = 801645133866074240, .offs = 47104, .shift = 54 },
    .{ .mask = 18085043175964672, .magic = 149550769766672, .offs = 48128, .shift = 54 },
    .{ .mask = 36170086385483776, .magic = 2161728379483603220, .offs = 49152, .shift = 53 },
    .{ .mask = 283115671060736, .magic = 18084769409531960, .offs = 51200, .shift = 53 },
    .{ .mask = 565681586307584, .magic = 9277432825647210496, .offs = 53248, .shift = 54 },
    .{ .mask = 1130822006735872, .magic = 17729641791746, .offs = 54272, .shift = 54 },
    .{ .mask = 2261102847592448, .magic = 576601558519646208, .offs = 55296, .shift = 54 },
    .{ .mask = 4521664529305600, .magic = 3520653420398592, .offs = 56320, .shift = 54 },
    .{ .mask = 9042787892731904, .magic = 576601498390103040, .offs = 57344, .shift = 54 },
    .{ .mask = 18085034619584512, .magic = 1515742766783529472, .offs = 58368, .shift = 54 },
    .{ .mask = 36170077829103616, .magic = 38562107796490370, .offs = 59392, .shift = 53 },
    .{ .mask = 420017753620736, .magic = 36028934462128128, .offs = 61440, .shift = 53 },
    .{ .mask = 699298018886144, .magic = 90072164614610944, .offs = 63488, .shift = 54 },
    .{ .mask = 1260057572672512, .magic = 72129062830669842, .offs = 64512, .shift = 54 },
    .{ .mask = 2381576680245248, .magic = 292734525669146644, .offs = 65536, .shift = 54 },
    .{ .mask = 4624614895390720, .magic = 9156737132199940, .offs = 66560, .shift = 54 },
    .{ .mask = 9110691325681664, .magic = 1441154079848956032, .offs = 67584, .shift = 54 },
    .{ .mask = 18082844186263552, .magic = 324260282614677512, .offs = 68608, .shift = 54 },
    .{ .mask = 36167887395782656, .magic = 5188192222289461249, .offs = 69632, .shift = 53 },
    .{ .mask = 35466950888980736, .magic = 18084767798919552, .offs = 71680, .shift = 53 },
    .{ .mask = 34905104758997504, .magic = 1733925750374990336, .offs = 73728, .shift = 54 },
    .{ .mask = 34344362452452352, .magic = 55733566890344960, .offs = 74752, .shift = 54 },
    .{ .mask = 33222877839362048, .magic = 4756381752939776256, .offs = 75776, .shift = 54 },
    .{ .mask = 30979908613181440, .magic = 18018796690243712, .offs = 76800, .shift = 54 },
    .{ .mask = 26493970160820224, .magic = 2305845208304091264, .offs = 77824, .shift = 54 },
    .{ .mask = 17522093256097792, .magic = 1729399923318854656, .offs = 78848, .shift = 54 },
    .{ .mask = 35607136465616896, .magic = 9025152226492928, .offs = 79872, .shift = 53 },
    .{ .mask = 9079539427579068672, .magic = 2316262052265467969, .offs = 81920, .shift = 52 },
    .{ .mask = 8935706818303361536, .magic = 2392812182241561, .offs = 86016, .shift = 53 },
    .{ .mask = 8792156787827803136, .magic = 2449967130889699585, .offs = 88064, .shift = 53 },
    .{ .mask = 8505056726876686336, .magic = 1407413806702597, .offs = 90112, .shift = 53 },
    .{ .mask = 7930856604974452736, .magic = 18577365791690754, .offs = 92160, .shift = 53 },
    .{ .mask = 6782456361169985536, .magic = 4616471129572507713, .offs = 94208, .shift = 53 },
    .{ .mask = 4485655873561051136, .magic = 2964530747459240068, .offs = 96256, .shift = 53 },
    .{ .mask = 9115426935197958144, .magic = 9232379377910562946, .offs = 98304, .shift = 52 },
};
var bishop_attacks: [bishop_array_size]u64 align(std.mem.page_size) = undefined;
var rook_attacks: [rook_array_size]u64 align(std.mem.page_size) = undefined;

pub fn init() void {
    magics_generation.generateBishopAttackArrayInPlace(bishop_magics, &bishop_attacks);
    magics_generation.generateRookAttackArrayInPlace(rook_magics, &rook_attacks);
}

pub fn getBishopAttacks(square: Square, blockers: u64) u64 {
    return (&bishop_attacks)[@intCast(bishop_magics[square.toInt()].getBishopIndex(blockers))];
}
pub fn getRookAttacks(square: Square, blockers: u64) u64 {
    return (&rook_attacks)[@intCast(rook_magics[square.toInt()].getRookIndex(blockers))];
}
