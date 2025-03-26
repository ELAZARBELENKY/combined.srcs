//*
//*  Copyright � 2024 FortifyIQ, Inc.
//*
//*  All Rights Reserved.
//*
//*  All information contained herein is, and remains, the property of FortifyIQ, Inc.
//*  Dissemination of this information or reproduction of this material, in any medium,
//*  is strictly forbidden unless prior written permission is obtained from FortifyIQ, Inc.
//*
//*
`timescale 1ns / 1ps
`include "defines.v"

package lw_sha_pkg;

`ifdef CORE_ARCH_S64
  parameter logic [`WORD_SIZE-1:0] standard_initial_state[6][7:0] =
 '{'{64'h6a09e667, 64'hbb67ae85,
     64'h3c6ef372, 64'ha54ff53a,
     64'h510e527f, 64'h9b05688c,
     64'h1f83d9ab, 64'h5be0cd19}, //256
  
 '{64'hc1059ed8, 64'h367cd507,
   64'h3070dd17, 64'hf70e5939,
   64'hffc00b31, 64'h68581511,
   64'h64f98fa7, 64'hbefa4fa4}, //224
  
 '{64'h6a09e667f3bcc908, 64'hbb67ae8584caa73b,
   64'h3c6ef372fe94f82b, 64'ha54ff53a5f1d36f1,
   64'h510e527fade682d1, 64'h9b05688c2b3e6c1f,
   64'h1f83d9abfb41bd6b, 64'h5be0cd19137e2179}, //512
  
 '{64'hcbbb9d5dc1059ed8, 64'h629a292a367cd507,
   64'h9159015a3070dd17, 64'h152fecd8f70e5939,
   64'h67332667ffc00b31, 64'h8eb44a8768581511,
   64'hdb0c2e0d64f98fa7, 64'h47b5481dbefa4fa4}, //384
  
 '{64'h22312194fc2bf72c, 64'h9f555fa3c84c64c2,
   64'h2393b86b6f53b151, 64'h963877195940eabd,
   64'h96283ee2a88effe3, 64'hbe5e1e2553863992,
   64'h2b0199fc2c85b8aa, 64'h0eb72ddC81c52ca2}, //512-256
  
 '{64'h8c3d37c819544da2, 64'h73e1996689dcd4d6,
   64'h1dfab7ae32ff9c82, 64'h679dd514582f9fcf,
   64'h0f6d2b697bd44da8, 64'h77e36f7304C48942,
   64'h3f9d85a86a1d36C8, 64'h1112e6ad91d692a1} //512-224
  };
  
  parameter logic [`WORD_SIZE-1:0] k256[64] =
 {32'h428a2f98, 32'h71374491, 32'hb5c0fbcf, 32'he9b5dba5,
  32'h3956c25b, 32'h59f111f1, 32'h923f82a4, 32'hab1c5ed5,
  32'hd807aa98, 32'h12835b01, 32'h243185be, 32'h550c7dc3,
  32'h72be5d74, 32'h80deb1fe, 32'h9bdc06a7, 32'hc19bf174,
  32'he49b69c1, 32'hefbe4786, 32'h0fc19dc6, 32'h240ca1cc,
  32'h2de92c6f, 32'h4a7484aa, 32'h5cb0a9dc, 32'h76f988da,
  32'h983e5152, 32'ha831c66d, 32'hb00327c8, 32'hbf597fc7,
  32'hc6e00bf3, 32'hd5a79147, 32'h06ca6351, 32'h14292967,
  32'h27b70a85, 32'h2e1b2138, 32'h4d2c6dfc, 32'h53380d13,
  32'h650a7354, 32'h766a0abb, 32'h81c2c92e, 32'h92722c85,
  32'ha2bfe8a1, 32'ha81a664b, 32'hc24b8b70, 32'hc76c51a3,
  32'hd192e819, 32'hd6990624, 32'hf40e3585, 32'h106aa070,
  32'h19a4c116, 32'h1e376c08, 32'h2748774c, 32'h34b0bcb5,
  32'h391c0cb3, 32'h4ed8aa4a, 32'h5b9cca4f, 32'h682e6ff3,
  32'h748f82ee, 32'h78a5636f, 32'h84c87814, 32'h8cc70208,
  32'h90befffa, 32'ha4506ceb, 32'hbef9a3f7, 32'hc67178f2};
  
  parameter logic [`WORD_SIZE-1:0] k512[80] =
 {64'h428a2f98d728ae22, 64'h7137449123ef65cd, 64'hb5c0fbcfec4d3b2f, 64'he9b5dba58189dbbc, 64'h3956c25bf348b538,
  64'h59f111f1b605d019, 64'h923f82a4af194f9b, 64'hab1c5ed5da6d8118, 64'hd807aa98a3030242, 64'h12835b0145706fbe,
  64'h243185be4ee4b28c, 64'h550c7dc3d5ffb4e2, 64'h72be5d74f27b896f, 64'h80deb1fe3b1696b1, 64'h9bdc06a725c71235,
  64'hc19bf174cf692694, 64'he49b69c19ef14ad2, 64'hefbe4786384f25e3, 64'h0fc19dc68b8cd5b5, 64'h240ca1cc77ac9c65,
  64'h2de92c6f592b0275, 64'h4a7484aa6ea6e483, 64'h5cb0a9dcbd41fbd4, 64'h76f988da831153b5, 64'h983e5152ee66dfab,
  64'ha831c66d2db43210, 64'hb00327c898fb213f, 64'hbf597fc7beef0ee4, 64'hc6e00bf33da88fc2, 64'hd5a79147930aa725,
  64'h06ca6351e003826f, 64'h142929670a0e6e70, 64'h27b70a8546d22ffc, 64'h2e1b21385c26c926, 64'h4d2c6dfc5ac42aed,
  64'h53380d139d95b3df, 64'h650a73548baf63de, 64'h766a0abb3c77b2a8, 64'h81c2c92e47edaee6, 64'h92722c851482353b,
  64'ha2bfe8a14cf10364, 64'ha81a664bbc423001, 64'hc24b8b70d0f89791, 64'hc76c51a30654be30, 64'hd192e819d6ef5218,
  64'hd69906245565a910, 64'hf40e35855771202a, 64'h106aa07032bbd1b8, 64'h19a4c116b8d2d0c8, 64'h1e376c085141ab53,
  64'h2748774cdf8eeb99, 64'h34b0bcb5e19b48a8, 64'h391c0cb3c5c95a63, 64'h4ed8aa4ae3418acb, 64'h5b9cca4f7763e373,
  64'h682e6ff3d6b2b8a3, 64'h748f82ee5defb2fc, 64'h78a5636f43172f60, 64'h84c87814a1f0ab72, 64'h8cc702081a6439ec,
  64'h90befffa23631e28, 64'ha4506cebde82bde9, 64'hbef9a3f7b2c67915, 64'hc67178f2e372532b, 64'hca273eceea26619c,
  64'hd186b8c721c0c207, 64'heada7dd6cde0eb1e, 64'hf57d4f7fee6ed178, 64'h06f067aa72176fba, 64'h0a637dc5a2c898a6,
  64'h113f9804bef90dae, 64'h1b710b35131c471b, 64'h28db77f523047d84, 64'h32caab7b40c72493, 64'h3c9ebe0a15c9bebc,
  64'h431d67c49c100d4c, 64'h4cc5d4becb3e42b6, 64'h597f299cfc657e2a, 64'h5fcb6fab3ad6faec, 64'h6c44198c4a475817};
  
    //read_word
    function automatic logic [`WORD_SIZE-1:0] read_word(input [`WORD_SIZE+$clog2(`WORD_SIZE)-1:0] x, input mode);
        return {right_rotate(x[`WORD_SIZE-1:0],  (mode ? `WORD_SIZE:`WORD_SIZE/2) - x[`WORD_SIZE+$clog2(`WORD_SIZE)-1-:$clog2(`WORD_SIZE)], mode)};
    endfunction

    //write_word
    function automatic logic [`WORD_SIZE+$clog2(`WORD_SIZE)-1:0] write_word(input [`WORD_SIZE-1:0] x, input [$clog2(`WORD_SIZE)-1:0] random, input mode);
        return {(mode ? random : random[$clog2(`WORD_SIZE)-2:0]), right_rotate(x, (mode ? random : random[$clog2(`WORD_SIZE)-2:0]), mode)};
    endfunction

    //right_rotate
    function automatic logic [`WORD_SIZE-1:0] right_rotate(input [`WORD_SIZE-1:0] x, input [$clog2(`WORD_SIZE)-1:0] n, input mode);
        return mode ?
        x >> n | x << (`WORD_SIZE - n):
        x[`WORD_SIZE/2-1:0] >> n | x[`WORD_SIZE/2-1:0] << (`WORD_SIZE/2 - n);
    endfunction
`else `ifdef CORE_ARCH_S32
    parameter logic [`WORD_SIZE-1:0] standard_initial_state256 [7:0] =
                               {32'h6a09e667, 32'hbb67ae85,
                                32'h3c6ef372, 32'ha54ff53a,
                                32'h510e527f, 32'h9b05688c,
                                32'h1f83d9ab, 32'h5be0cd19};
      
    parameter logic [`WORD_SIZE-1:0] standard_initial_state224 [7:0] =
   {32'hc1059ed8, 32'h367cd507,
    32'h3070dd17, 32'hf70e5939,
    32'hffc00b31, 32'h68581511,
    32'h64f98fa7, 32'hbefa4fa4};
    
    parameter logic [`WORD_SIZE-1:0] k [64] =
           {32'h428a2f98, 32'h71374491, 32'hb5c0fbcf, 32'he9b5dba5,
            32'h3956c25b, 32'h59f111f1, 32'h923f82a4, 32'hab1c5ed5,
            32'hd807aa98, 32'h12835b01, 32'h243185be, 32'h550c7dc3,
            32'h72be5d74, 32'h80deb1fe, 32'h9bdc06a7, 32'hc19bf174,
            32'he49b69c1, 32'hefbe4786, 32'h0fc19dc6, 32'h240ca1cc,
            32'h2de92c6f, 32'h4a7484aa, 32'h5cb0a9dc, 32'h76f988da,
            32'h983e5152, 32'ha831c66d, 32'hb00327c8, 32'hbf597fc7,
            32'hc6e00bf3, 32'hd5a79147, 32'h06ca6351, 32'h14292967,
            32'h27b70a85, 32'h2e1b2138, 32'h4d2c6dfc, 32'h53380d13,
            32'h650a7354, 32'h766a0abb, 32'h81c2c92e, 32'h92722c85,
            32'ha2bfe8a1, 32'ha81a664b, 32'hc24b8b70, 32'hc76c51a3,
            32'hd192e819, 32'hd6990624, 32'hf40e3585, 32'h106aa070,
            32'h19a4c116, 32'h1e376c08, 32'h2748774c, 32'h34b0bcb5,
            32'h391c0cb3, 32'h4ed8aa4a, 32'h5b9cca4f, 32'h682e6ff3,
            32'h748f82ee, 32'h78a5636f, 32'h84c87814, 32'h8cc70208,
            32'h90befffa, 32'ha4506ceb, 32'hbef9a3f7, 32'hc67178f2};

    //read_word
    function automatic logic [`WORD_SIZE-1:0] read_word(input [`WORD_SIZE+$clog2(`WORD_SIZE)-1:0] x);
        return {right_rotate(x[`WORD_SIZE-1:0],`WORD_SIZE - x[`WORD_SIZE+$clog2(`WORD_SIZE)-1-:$clog2(`WORD_SIZE)])};
    endfunction
     
    //write_word
    function automatic logic [`WORD_SIZE+$clog2(`WORD_SIZE)-1:0] write_word(input [`WORD_SIZE-1:0] x, input [$clog2(`WORD_SIZE)-1:0] random);
        return {random , right_rotate(x, random)};
    endfunction

    //right_rotate
    function automatic logic [`WORD_SIZE-1:0] right_rotate(input [`WORD_SIZE-1:0] x, input [$clog2(`WORD_SIZE)-1:0] n);
        return x >> n | x << (`WORD_SIZE - {27'b0,n});
    endfunction
`endif `endif
endpackage