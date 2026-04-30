% ============================================================================
% dpa_engine.m — Differential Power Analysis on AES VCD Data
% Implements CPA (Correlation Power Analysis) attack on AES-128.
% Correlates toggle vectors with hypothetical key byte values.
% Recovers partial key bytes and plots correlation traces.
%
% Usage:
%   dpa_results = dpa_engine(parsed_aes_vcd_data);
%   dpa_results = dpa_engine(parsed_aes_vcd_data, 'TargetByte', 0);
%
% Output struct fields:
%   dpa_results.recovered_key_bytes — [16 x 1] recovered key byte values
%   dpa_results.correlation_traces  — [256 x num_ts] per target byte
%   dpa_results.confidence          — Confidence score per recovered byte
%   dpa_results.success_rate        — Fraction of correctly recovered bytes
% ============================================================================

function dpa_results = dpa_engine(vcd_data, varargin)

    fprintf('\n========================================\n');
    fprintf(' dpa_engine: Differential Power Analysis\n');
    fprintf('========================================\n');

    % ---- Parse optional parameters ----
    p = inputParser;
    addParameter(p, 'TargetByte', -1);      % -1 = attack all 16 bytes
    addParameter(p, 'NumTraces', 500);       % Number of power traces to use
    addParameter(p, 'KnownKey', []);         % Optional known key for validation
    parse(p, varargin{:});

    target_byte = p.Results.TargetByte;
    num_traces  = p.Results.NumTraces;
    known_key   = p.Results.KnownKey;

    % ---- Extract toggle data ----
    sig_names   = vcd_data.signal_names;
    widths      = vcd_data.signal_widths;
    toggles     = vcd_data.toggle_matrix;
    num_signals = length(sig_names);
    num_ts      = size(toggles, 2);

    fprintf('  Signals: %d, Time points: %d\n', num_signals, num_ts);

    % ---- Identify Trojan AES signals for power trace ----
    % Sum all trojan AES internal signals to create aggregate power trace
    trojan_sig_idx = [];
    clean_sig_idx  = [];

    for s = 1:num_signals
        name = lower(sig_names{s});
        if contains(name, 'trojan') && (contains(name, 'state') || ...
           contains(name, 'round') || contains(name, 'leak'))
            trojan_sig_idx(end+1) = s;
        elseif contains(name, 'clean') && (contains(name, 'state') || ...
               contains(name, 'round'))
            clean_sig_idx(end+1) = s;
        end
    end

    % Build aggregate power trace (sum of toggle activity)
    if ~isempty(trojan_sig_idx)
        power_trace_trojan = sum(toggles(trojan_sig_idx, :), 1);
    else
        % Fallback: use all non-control signals
        power_trace_trojan = sum(toggles, 1);
    end

    if ~isempty(clean_sig_idx)
        power_trace_clean = sum(toggles(clean_sig_idx, :), 1);
    else
        power_trace_clean = power_trace_trojan * 0.9;
    end

    % ---- AES S-Box for hypothetical power model ----
    sbox = [ ...
        99 124 119 123 242 107 111 197  48   1  103  43 254 215 171 118; ...
        202 130 201 125 250  89  71 240 173 212 162 175 156 164 114 192; ...
        183 253 147  38  54  63 247 204  52 165 229 241 113 216  49  21; ...
          4 199  35 195  24 150   5 154   7  18 128 226 235  39 178 117; ...
          9 131  44  26  27 110  90 160  82  59 214 179  41 227  47 132; ...
         83 209   0 237  32 252 177  91 106 203 190  57  74  76  88 207; ...
        208 239 170 251  67  77  51 133  69 249   2 127  80  60 159 168; ...
         81 163  64 143 146 157  56 245 188 182 218  33  16 255 243 210; ...
        205  12  19 236  95 151  68  23 196 167 126  61 100  93  25 115; ...
         96 129  79 220  34  42 144 136  70 238 184  20 222  94  11 219; ...
        224  50  58  10  73   6  36  92 194 211 172  98 145 149 228 121; ...
        231 200  55 109 141 213  78 169 108  86 244 234 101 122 174   8; ...
        186 120  37  46  28 166 180 198 232 221 116  31  75 189 139 138; ...
        112  62 181 102  72   3 246  14  97  53  87 185 134 193  29 158; ...
        225 248 152  17 105 217 142 148 155  30 135 233 206  85  40 223; ...
        140 161 137  13 191 230  66 104  65 153  45  15 176  84 187  22  ...
    ];
    sbox_flat = sbox';  % Linearize: sbox_flat(i+1) = S-Box[i]
    sbox_flat = sbox_flat(:)';

    % ---- Generate synthetic plaintexts (simulating what was used) ----
    rng(42);  % Same seed as testbench for consistency
    cycles_per_enc = 12;
    num_encryptions = floor(num_ts / cycles_per_enc);
    num_encryptions = min(num_encryptions, num_traces);

    fprintf('  Number of encryption traces: %d\n', num_encryptions);

    % Generate plaintext bytes (matching testbench generation)
    plaintexts = zeros(num_encryptions, 16);  % [num_enc x 16 bytes]
    for enc = 1:num_encryptions
        for b = 0:15
            plaintexts(enc, b+1) = mod(randi(256) - 1, 256);
        end
    end

    % Extract per-encryption power traces
    enc_power_traces = zeros(num_encryptions, cycles_per_enc);
    for enc = 1:num_encryptions
        ts_start = (enc-1) * cycles_per_enc + 1;
        ts_end   = min(enc * cycles_per_enc, num_ts);
        if ts_end > num_ts, break; end
        enc_power_traces(enc, 1:ts_end-ts_start+1) = ...
            power_trace_trojan(ts_start:ts_end);
    end

    % ---- CPA Attack: correlate hypothetical power with actual power ----
    if target_byte == -1
        target_bytes = 0:15;
    else
        target_bytes = target_byte;
    end

    recovered_key = zeros(16, 1);
    confidence    = zeros(16, 1);
    all_corr_traces = cell(16, 1);

    for tb = target_bytes
        byte_idx = tb + 1;
        fprintf('  Attacking key byte %d...', tb);

        % Hypothetical intermediate values for all 256 key guesses
        % H(p, k) = HW(S-Box[p XOR k])  (Hamming Weight model)
        hyp_power = zeros(num_encryptions, 256);
        for k = 0:255
            for enc = 1:num_encryptions
                pt_byte = plaintexts(enc, byte_idx);
                sbox_out = sbox_flat(bitxor(pt_byte, k) + 1);
                % Hamming weight as power model
                hyp_power(enc, k+1) = sum(bitget(sbox_out, 1:8));
            end
        end

        % Correlation: for each key guess, correlate hyp_power with each
        % time point in the actual power trace
        num_time_pts = size(enc_power_traces, 2);
        corr_matrix = zeros(256, num_time_pts);

        for k = 0:255
            h = hyp_power(:, k+1);
            h_centered = h - mean(h);
            h_norm = sqrt(sum(h_centered.^2));

            if h_norm < 1e-10, continue; end

            for t = 1:num_time_pts
                p_col = enc_power_traces(:, t);
                p_centered = p_col - mean(p_col);
                p_norm = sqrt(sum(p_centered.^2));

                if p_norm < 1e-10, continue; end

                corr_matrix(k+1, t) = sum(h_centered .* p_centered) / (h_norm * p_norm);
            end
        end

        % Find key guess with highest absolute correlation
        [max_corr_per_key, ~] = max(abs(corr_matrix), [], 2);
        [best_corr, best_key] = max(max_corr_per_key);
        recovered_key(byte_idx) = best_key - 1;  % 0-indexed
        confidence(byte_idx) = best_corr;

        % Store correlation traces
        all_corr_traces{byte_idx} = corr_matrix;

        % Second-best for confidence margin
        sorted_corr = sort(max_corr_per_key, 'descend');
        margin = sorted_corr(1) - sorted_corr(2);

        fprintf(' recovered=0x%02X, corr=%.4f, margin=%.4f\n', ...
            recovered_key(byte_idx), best_corr, margin);
    end

    % ---- Validation against known key ----
    success_rate = 0;
    if ~isempty(known_key)
        correct = sum(recovered_key == known_key(:));
        success_rate = correct / 16;
        fprintf('\n  Key recovery success rate: %d/16 (%.1f%%)\n', correct, success_rate*100);
    end

    % ---- Visualization ----
    results_dir = 'results';
    if ~exist(results_dir, 'dir'), mkdir(results_dir); end

    figure('Position', [100, 100, 1400, 900], 'Visible', 'off');

    % Plot 1: Correlation traces for first 4 target bytes
    for plot_idx = 1:min(4, length(target_bytes))
        subplot(3, 2, plot_idx);
        byte_idx = target_bytes(plot_idx) + 1;
        corr_mat = all_corr_traces{byte_idx};

        if ~isempty(corr_mat)
            hold on;
            % Plot all 256 key guesses in gray
            for k = 1:256
                plot(1:size(corr_mat, 2), corr_mat(k, :), 'Color', [0.8 0.8 0.8 0.3], 'LineWidth', 0.3);
            end
            % Highlight correct/recovered key in red
            best_k = recovered_key(byte_idx) + 1;
            plot(1:size(corr_mat, 2), corr_mat(best_k, :), 'r', 'LineWidth', 2);
            hold off;
        end

        ylabel('Correlation');
        xlabel('Time Point');
        title(sprintf('Byte %d — Recovered: 0x%02X (r=%.3f)', ...
            target_bytes(plot_idx), recovered_key(byte_idx), confidence(byte_idx)));
        grid on;
        ylim([-1 1]);
    end

    % Plot 5: Confidence bar chart
    subplot(3, 2, 5);
    bar_c = zeros(16, 3);
    for b = 1:16
        if confidence(b) > 0.5
            bar_c(b, :) = [0.2 0.7 0.3];  % High confidence = green
        elseif confidence(b) > 0.3
            bar_c(b, :) = [0.9 0.7 0.1];  % Medium = yellow
        else
            bar_c(b, :) = [0.85 0.15 0.15]; % Low = red
        end
    end
    b_h = bar(confidence);
    b_h.FaceColor = 'flat';
    b_h.CData = bar_c;
    xlabel('Key Byte Index');
    ylabel('Peak Correlation');
    title('DPA Confidence per Key Byte');
    grid on;

    % Plot 6: Recovered key display
    subplot(3, 2, 6);
    axis off;
    key_hex = sprintf('%02X ', recovered_key);
    text(0.5, 0.7, 'Recovered Key Bytes:', 'FontSize', 13, ...
        'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(0.5, 0.45, key_hex, 'FontSize', 11, 'FontFamily', 'Courier', ...
        'HorizontalAlignment', 'center', 'Color', [0.8 0.1 0.1]);
    text(0.5, 0.2, sprintf('Average confidence: %.3f', mean(confidence)), ...
        'FontSize', 11, 'HorizontalAlignment', 'center');
    if ~isempty(known_key)
        text(0.5, 0.05, sprintf('Success rate: %.1f%%', success_rate*100), ...
            'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
            'Color', [0 0.5 0]);
    end

    sgtitle('Differential Power Analysis — CPA Attack on AES-128', ...
        'FontSize', 14, 'FontWeight', 'bold');
    saveas(gcf, fullfile(results_dir, 'dpa_correlation.png'));
    fprintf('\n  Saved: %s\n', fullfile(results_dir, 'dpa_correlation.png'));

    % ---- Assemble output ----
    dpa_results.recovered_key_bytes = recovered_key;
    dpa_results.correlation_traces  = all_corr_traces;
    dpa_results.confidence          = confidence;
    dpa_results.success_rate        = success_rate;
    dpa_results.plaintexts          = plaintexts;
    dpa_results.enc_power_traces    = enc_power_traces;
    dpa_results.target_bytes        = target_bytes;

    fprintf('\n  dpa_engine complete.\n');
end
