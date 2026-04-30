% ============================================================================
% power_model.m — Dynamic Power Estimation from Toggle Vectors
% Implements P = α × C × V² × f dynamic power estimation.
% Uses a simplified cell capacitance lookup table for common logic cells.
% Outputs milliwatt-level power deviation between clean vs Trojan signals.
%
% Usage:
%   power_data = power_model(parsed_vcd_data);
%   power_data = power_model(parsed_vcd_data, 'Voltage', 1.1, 'Frequency', 100e6);
%
% Output struct fields:
%   power_data.signal_names       — Cell array of signal names
%   power_data.power_per_signal   — [num_signals x 1] average power (mW)
%   power_data.power_traces       — [num_signals x num_ts] instantaneous power (mW)
%   power_data.alpha_per_signal   — Activity factor per signal
%   power_data.clean_total_power  — Total clean design power (mW)
%   power_data.trojan_total_power — Total Trojan design power (mW)
%   power_data.power_deviation    — Per-signal deviation (mW)
%   power_data.deviation_pct      — Per-signal deviation (%)
% ============================================================================

function power_data = power_model(vcd_data, varargin)

    fprintf('\n========================================\n');
    fprintf(' power_model: Dynamic Power Estimation\n');
    fprintf('========================================\n');

    % ---- Parse optional parameters ----
    p = inputParser;
    addParameter(p, 'Voltage',   1.2);       % Supply voltage (V) — typical for 45nm
    addParameter(p, 'Frequency', 100e6);     % Clock frequency (Hz) — 100 MHz
    addParameter(p, 'Technology', '45nm');    % Technology node
    parse(p, varargin{:});

    Vdd   = p.Results.Voltage;
    f_clk = p.Results.Frequency;
    tech  = p.Results.Technology;

    fprintf('  Technology: %s\n', tech);
    fprintf('  Supply Voltage: %.2f V\n', Vdd);
    fprintf('  Clock Frequency: %.1f MHz\n', f_clk / 1e6);

    % ============================================================================
    % Simplified Cell Capacitance Lookup Table (pF per bit)
    % Based on typical 45nm standard cell library values
    % ============================================================================
    cap_table = struct();
    cap_table.wire_1bit    = 0.005;   % Routing wire (pF/bit)
    cap_table.flop_1bit    = 0.012;   % D flip-flop (pF/bit)
    cap_table.logic_1bit   = 0.008;   % Combinational gate (pF/bit)
    cap_table.sbox_8bit    = 0.150;   % AES S-Box (pF per 8-bit lookup)
    cap_table.adder_4bit   = 0.040;   % 4-bit ripple carry adder (pF)
    cap_table.xor_128bit   = 0.800;   % 128-bit XOR (pF)
    cap_table.counter_14bit = 0.200;  % 14-bit counter (pF)
    cap_table.mux_4bit     = 0.025;   % 4-bit multiplexer (pF)
    cap_table.reg_128bit   = 1.600;   % 128-bit register file (pF)

    fprintf('  Capacitance model loaded (%s)\n', tech);

    % ---- Extract data from parsed VCD ----
    num_signals  = length(vcd_data.signal_names);
    num_ts       = size(vcd_data.toggle_matrix, 2);
    widths       = vcd_data.signal_widths;
    toggles      = vcd_data.toggle_matrix;
    sig_names    = vcd_data.signal_names;

    % ---- Compute activity factor (α) per signal ----
    % α = (total toggles) / (num_timestamps × signal_width)
    alpha = zeros(num_signals, 1);
    for s = 1:num_signals
        total_t = sum(toggles(s, :));
        if num_ts > 0 && widths(s) > 0
            alpha(s) = total_t / (num_ts * widths(s));
        end
    end

    % ---- Assign capacitance per signal based on name/type ----
    cap_per_signal = zeros(num_signals, 1);

    for s = 1:num_signals
        name = lower(sig_names{s});
        w = widths(s);

        if contains(name, 'clk') || contains(name, 'clock')
            cap_per_signal(s) = cap_table.wire_1bit * 5;  % Clock tree
        elseif contains(name, 'rst') || contains(name, 'reset')
            cap_per_signal(s) = cap_table.wire_1bit * 3;
        elseif contains(name, 'state') && w >= 64
            cap_per_signal(s) = cap_table.reg_128bit * (w / 128);
        elseif contains(name, 'round_key') || contains(name, 'key')
            cap_per_signal(s) = cap_table.reg_128bit * (w / 128);
        elseif contains(name, 'ciphertext') || contains(name, 'plaintext')
            cap_per_signal(s) = cap_table.reg_128bit * (w / 128);
        elseif contains(name, 'trojan_leak')
            cap_per_signal(s) = cap_table.reg_128bit * (w / 128);
        elseif contains(name, 'sbox') || contains(name, 'sub')
            cap_per_signal(s) = cap_table.sbox_8bit * ceil(w / 8);
        elseif contains(name, 'counter') || contains(name, 'op_counter')
            cap_per_signal(s) = cap_table.counter_14bit * (w / 14);
        elseif contains(name, 'result') && w <= 4
            cap_per_signal(s) = cap_table.adder_4bit;
        elseif contains(name, 'trojan_trigger')
            cap_per_signal(s) = cap_table.logic_1bit * w;
        elseif contains(name, 'seq_state') || contains(name, 'payload')
            cap_per_signal(s) = cap_table.flop_1bit * w;
        elseif contains(name, 'round')
            cap_per_signal(s) = cap_table.flop_1bit * w;
        elseif contains(name, 'busy') || contains(name, 'done')
            cap_per_signal(s) = cap_table.flop_1bit;
        elseif w >= 32
            cap_per_signal(s) = cap_table.flop_1bit * w;
        else
            cap_per_signal(s) = cap_table.logic_1bit * w;
        end
    end

    % ---- Compute instantaneous power: P(t) = α(t) × C × V² × f ----
    % α(t) = toggles(s,t) / width(s) for each timestamp
    power_traces = zeros(num_signals, num_ts);

    for s = 1:num_signals
        for t = 1:num_ts
            alpha_t = toggles(s, t) / max(widths(s), 1);
            % P = α × C × V² × f  (in Watts)
            P_watts = alpha_t * cap_per_signal(s) * 1e-12 * Vdd^2 * f_clk;
            power_traces(s, t) = P_watts * 1e3;  % Convert to mW
        end
    end

    % ---- Average power per signal ----
    avg_power = mean(power_traces, 2);

    % ---- Classify signals: clean vs Trojan ----
    clean_mask  = false(num_signals, 1);
    trojan_mask = false(num_signals, 1);

    for s = 1:num_signals
        name = lower(sig_names{s});
        if contains(name, 'clean') || ...
           (contains(name, 'u_clean') && ~contains(name, 'trojan'))
            clean_mask(s) = true;
        elseif contains(name, 'trojan') || contains(name, 'comb') || ...
               contains(name, 'seq') || contains(name, 'counter')
            trojan_mask(s) = true;
        end
    end

    clean_total  = sum(avg_power(clean_mask));
    trojan_total = sum(avg_power(trojan_mask));

    % ---- Compute power deviation per signal ----
    % For matched clean/trojan signal pairs
    deviation_mw  = zeros(num_signals, 1);
    deviation_pct = zeros(num_signals, 1);

    % Find matching pairs (e.g., u_clean.result vs u_comb.result)
    for s = 1:num_signals
        name = sig_names{s};
        if trojan_mask(s)
            % Try to find clean counterpart
            clean_name = strrep(strrep(strrep(strrep(name, ...
                'u_comb', 'u_clean'), 'u_seq', 'u_clean'), ...
                'u_counter', 'u_clean'), 'u_aes_trojan', 'u_aes_clean');
            clean_idx = find(strcmp(sig_names, clean_name));
            if ~isempty(clean_idx)
                deviation_mw(s)  = avg_power(s) - avg_power(clean_idx(1));
                if avg_power(clean_idx(1)) > 0
                    deviation_pct(s) = (deviation_mw(s) / avg_power(clean_idx(1))) * 100;
                end
            end
        end
    end

    % ---- Generate Power Deviation Bar Chart ----
    figure('Position', [100, 100, 1200, 700], 'Visible', 'off');

    % Find signals with non-zero deviation
    dev_idx = find(abs(deviation_mw) > 1e-6);

    if ~isempty(dev_idx)
        subplot(2,1,1);
        bar_colors = zeros(length(dev_idx), 3);
        for k = 1:length(dev_idx)
            if deviation_mw(dev_idx(k)) > 0
                bar_colors(k, :) = [0.85 0.15 0.15];  % Red for positive (Trojan overhead)
            else
                bar_colors(k, :) = [0.15 0.65 0.15];  % Green for negative
            end
        end
        b = bar(deviation_mw(dev_idx));
        b.FaceColor = 'flat';
        b.CData = bar_colors;
        set(gca, 'XTickLabel', cellfun(@(s) strrep(s, 'alu_tb.', ''), ...
            sig_names(dev_idx), 'UniformOutput', false));
        xtickangle(45);
        ylabel('Power Deviation (mW)');
        title('Per-Signal Power Deviation: Trojan vs Clean');
        grid on;
    end

    % Total power comparison
    subplot(2,1,2);
    categories = {'Clean Design', 'Trojan Design(s)'};
    bar_vals = [clean_total, trojan_total];
    b2 = bar(bar_vals);
    b2.FaceColor = 'flat';
    b2.CData = [0.2 0.6 0.9; 0.9 0.2 0.2];
    set(gca, 'XTickLabel', categories);
    ylabel('Total Average Power (mW)');
    title(sprintf('Total Dynamic Power Comparison (Vdd=%.2fV, f=%dMHz)', Vdd, round(f_clk/1e6)));
    grid on;

    % Annotate with values
    for k = 1:2
        text(k, bar_vals(k), sprintf('%.4f mW', bar_vals(k)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontWeight', 'bold', 'FontSize', 11);
    end

    sgtitle('Dynamic Power Model — P = \alpha \times C \times V^2 \times f', ...
        'FontSize', 14, 'FontWeight', 'bold');

    results_dir = 'results';
    if ~exist(results_dir, 'dir'), mkdir(results_dir); end
    saveas(gcf, fullfile(results_dir, 'power_deviation.png'));
    fprintf('\n  Saved: %s\n', fullfile(results_dir, 'power_deviation.png'));

    % ---- Generate Per-Signal Power Traces ----
    figure('Position', [100, 100, 1400, 600], 'Visible', 'off');

    % Plot power traces for result signals
    result_idx = find(cellfun(@(s) contains(lower(s), 'result'), sig_names));
    if length(result_idx) >= 2
        num_plots = min(length(result_idx), 4);
        colors = [0.2 0.4 0.8; 0.85 0.15 0.15; 0.6 0.2 0.6; 0.8 0.4 0.0];

        for k = 1:num_plots
            subplot(num_plots, 1, k);
            idx = result_idx(k);
            % Smooth for visualization
            window = min(50, floor(num_ts/10));
            if window > 1
                smoothed = movmean(power_traces(idx, :), window);
            else
                smoothed = power_traces(idx, :);
            end
            plot(1:num_ts, smoothed, 'Color', colors(k,:), 'LineWidth', 0.8);
            ylabel('Power (mW)');
            short_name = strrep(sig_names{idx}, 'alu_tb.', '');
            short_name = strrep(short_name, 'aes_tb.', '');
            title(sprintf('Power Trace: %s', short_name));
            grid on;
        end
        xlabel('Time Step');
    end

    sgtitle('Instantaneous Power Traces (Moving Average)', 'FontSize', 13);
    saveas(gcf, fullfile(results_dir, 'power_traces.png'));
    fprintf('  Saved: %s\n', fullfile(results_dir, 'power_traces.png'));

    % ---- Print Summary Table ----
    fprintf('\n  Power Estimation Summary:\n');
    fprintf('  %-50s  α-factor   C(pF)    P_avg(mW)   Dev(mW)\n', 'Signal');
    fprintf('  %s\n', repmat('-', 1, 95));

    [~, pwr_sort] = sort(avg_power, 'descend');
    for k = 1:min(20, num_signals)
        idx = pwr_sort(k);
        fprintf('  %-50s  %.4f    %.4f   %.6f    %+.6f\n', ...
            sig_names{idx}, alpha(idx), cap_per_signal(idx), ...
            avg_power(idx), deviation_mw(idx));
    end

    fprintf('\n  Clean total power:  %.6f mW\n', clean_total);
    fprintf('  Trojan total power: %.6f mW\n', trojan_total);
    if clean_total > 0
        fprintf('  Trojan overhead:    %+.2f%%\n', ...
            (trojan_total - clean_total) / clean_total * 100);
    end

    % ---- Assemble output ----
    power_data.signal_names       = sig_names;
    power_data.power_per_signal   = avg_power;
    power_data.power_traces       = power_traces;
    power_data.alpha_per_signal   = alpha;
    power_data.cap_per_signal     = cap_per_signal;
    power_data.clean_total_power  = clean_total;
    power_data.trojan_total_power = trojan_total;
    power_data.power_deviation    = deviation_mw;
    power_data.deviation_pct      = deviation_pct;
    power_data.Vdd                = Vdd;
    power_data.frequency          = f_clk;
    power_data.technology         = tech;

    fprintf('\n  power_model complete.\n');
end
