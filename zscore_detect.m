% ============================================================================
% zscore_detect.m — Z-Score Anomaly Detection for Hardware Trojan Detection
% Computes Z-score across toggle vectors from parsed VCD data.
% Flags signals beyond ±2.5 standard deviations as suspicious.
% Returns ranked list of anomalous signals.
%
% Usage:
%   results = zscore_detect(parsed_vcd_data);
%   results = zscore_detect(parsed_vcd_data, 'Threshold', 3.0);
%
% Output struct fields:
%   results.signal_names    — Cell array of all signal names
%   results.zscores         — [num_signals x 1] Z-scores based on total toggles
%   results.zscore_traces   — [num_signals x num_ts] per-timestamp Z-scores
%   results.suspicious      — Struct array of flagged signals (sorted by |Z|)
%   results.threshold       — Z-score threshold used
%   results.num_flagged     — Number of signals flagged
% ============================================================================

function results = zscore_detect(vcd_data, varargin)

    fprintf('\n========================================\n');
    fprintf(' zscore_detect: Z-Score Anomaly Detection\n');
    fprintf('========================================\n');

    % ---- Parse optional parameters ----
    p = inputParser;
    addParameter(p, 'Threshold', 2.5);      % Z-score threshold
    addParameter(p, 'WindowSize', 100);      % Sliding window for temporal Z-score
    addParameter(p, 'GroupByModule', true);   % Compare within module groups
    parse(p, varargin{:});

    threshold  = p.Results.Threshold;
    win_size   = p.Results.WindowSize;
    group_mode = p.Results.GroupByModule;

    fprintf('  Z-score threshold: ±%.1f σ\n', threshold);

    % ---- Extract data ----
    sig_names   = vcd_data.signal_names;
    widths      = vcd_data.signal_widths;
    toggles     = vcd_data.toggle_matrix;  % [num_signals x num_ts]
    num_signals = length(sig_names);
    num_ts      = size(toggles, 2);

    % ---- Normalize toggles by signal width ----
    % This makes comparison fair across signals of different bit-widths
    norm_toggles = zeros(size(toggles));
    for s = 1:num_signals
        if widths(s) > 0
            norm_toggles(s, :) = toggles(s, :) / widths(s);
        end
    end

    % ---- Method 1: Global Z-score on total toggle counts ----
    total_toggles = sum(norm_toggles, 2);  % [num_signals x 1]
    mu_global     = mean(total_toggles);
    sigma_global  = std(total_toggles);

    if sigma_global > 0
        zscores_global = (total_toggles - mu_global) / sigma_global;
    else
        zscores_global = zeros(num_signals, 1);
    end

    % ---- Method 2: Group-based Z-score (compare within module types) ----
    if group_mode
        zscores_grouped = zeros(num_signals, 1);
        groups = identify_signal_groups(sig_names);
        unique_groups = unique(groups);

        for g = 1:length(unique_groups)
            grp = unique_groups{g};
            grp_idx = find(strcmp(groups, grp));
            if length(grp_idx) < 2
                continue;
            end

            grp_totals = total_toggles(grp_idx);
            grp_mu     = mean(grp_totals);
            grp_sigma  = std(grp_totals);

            if grp_sigma > 0
                zscores_grouped(grp_idx) = (grp_totals - grp_mu) / grp_sigma;
            end
        end
    else
        zscores_grouped = zscores_global;
    end

    % Combine: use maximum absolute Z-score from both methods
    zscores_combined = zeros(num_signals, 1);
    for s = 1:num_signals
        if abs(zscores_grouped(s)) > abs(zscores_global(s))
            zscores_combined(s) = zscores_grouped(s);
        else
            zscores_combined(s) = zscores_global(s);
        end
    end

    % ---- Method 3: Temporal Z-score traces (sliding window) ----
    zscore_traces = zeros(num_signals, num_ts);
    actual_win = min(win_size, floor(num_ts / 4));

    if actual_win > 1 && num_ts > actual_win
        for s = 1:num_signals
            sig = norm_toggles(s, :);
            % Compute running mean and std
            for t = 1:num_ts
                win_start = max(1, t - actual_win + 1);
                win_data  = sig(win_start:t);
                w_mu      = mean(win_data);
                w_sigma   = std(win_data);
                if w_sigma > 0
                    zscore_traces(s, t) = (sig(t) - w_mu) / w_sigma;
                else
                    zscore_traces(s, t) = 0;
                end
            end
        end
    end

    % ---- Flag suspicious signals ----
    flagged_idx  = find(abs(zscores_combined) > threshold);
    [~, rank_order] = sort(abs(zscores_combined(flagged_idx)), 'descend');
    flagged_idx  = flagged_idx(rank_order);

    suspicious = struct('name', {}, 'index', {}, 'zscore', {}, ...
                        'total_toggles', {}, 'verdict', {});

    for k = 1:length(flagged_idx)
        idx = flagged_idx(k);
        suspicious(k).name          = sig_names{idx};
        suspicious(k).index         = idx;
        suspicious(k).zscore        = zscores_combined(idx);
        suspicious(k).total_toggles = sum(toggles(idx, :));
        if zscores_combined(idx) > threshold
            suspicious(k).verdict = 'ANOMALOUS (high activity)';
        else
            suspicious(k).verdict = 'ANOMALOUS (low activity)';
        end
    end

    % ---- Generate Visualization ----
    results_dir = 'results';
    if ~exist(results_dir, 'dir'), mkdir(results_dir); end

    % Plot 1: Z-score bar chart (all signals)
    figure('Position', [100, 100, 1400, 700], 'Visible', 'off');

    subplot(2,1,1);
    bar_colors = zeros(num_signals, 3);
    for s = 1:num_signals
        if abs(zscores_combined(s)) > threshold
            bar_colors(s, :) = [0.85 0.15 0.15];  % Red = suspicious
        else
            bar_colors(s, :) = [0.3 0.6 0.85];    % Blue = normal
        end
    end
    b = bar(zscores_combined);
    b.FaceColor = 'flat';
    b.CData = bar_colors;
    hold on;
    yline(threshold, '--r', sprintf('+%.1fσ', threshold), 'LineWidth', 1.5);
    yline(-threshold, '--r', sprintf('-%.1fσ', threshold), 'LineWidth', 1.5);
    yline(0, '-k', 'LineWidth', 0.5);
    ylabel('Z-Score');
    title('Signal Toggle Z-Scores — Anomaly Detection');

    % Truncate long names for x-axis
    short_names = cellfun(@(s) truncate_name(s), sig_names, 'UniformOutput', false);
    set(gca, 'XTick', 1:num_signals, 'XTickLabel', short_names);
    xtickangle(55);
    set(gca, 'FontSize', 7);
    grid on;

    % Plot 2: Temporal anomaly heatmap (top flagged signals)
    subplot(2,1,2);
    if ~isempty(flagged_idx) && num_ts > 0
        num_show = min(8, length(flagged_idx));
        show_idx = flagged_idx(1:num_show);
        imagesc(abs(zscore_traces(show_idx, :)));
        colormap(hot);
        colorbar;
        caxis([0, max(5, threshold * 2)]);
        yticks(1:num_show);
        yticklabels(cellfun(@(s) truncate_name(s), sig_names(show_idx), 'UniformOutput', false));
        xlabel('Time Step');
        ylabel('Signal');
        title('Temporal Z-Score Heatmap — Flagged Signals');
    else
        text(0.5, 0.5, 'No signals exceeded Z-score threshold', ...
            'HorizontalAlignment', 'center', 'FontSize', 14);
        axis off;
    end

    sgtitle(sprintf('Z-Score Anomaly Detection (threshold = ±%.1fσ)', threshold), ...
        'FontSize', 14, 'FontWeight', 'bold');
    saveas(gcf, fullfile(results_dir, 'zscore_detection.png'));
    fprintf('  Saved: %s\n', fullfile(results_dir, 'zscore_detection.png'));

    % ---- Print Results ----
    fprintf('\n  Z-Score Analysis Results:\n');
    fprintf('  %-50s  Z-Score    Total Toggles  Verdict\n', 'Signal');
    fprintf('  %s\n', repmat('-', 1, 100));

    if isempty(suspicious)
        fprintf('  No signals exceeded ±%.1fσ threshold.\n', threshold);
    else
        for k = 1:length(suspicious)
            fprintf('  %-50s  %+7.3f    %8d       %s\n', ...
                suspicious(k).name, suspicious(k).zscore, ...
                suspicious(k).total_toggles, suspicious(k).verdict);
        end
    end

    fprintf('\n  Total signals analyzed: %d\n', num_signals);
    fprintf('  Signals flagged:       %d\n', length(suspicious));
    fprintf('  Threshold:             ±%.1fσ\n', threshold);

    % ---- Assemble output ----
    results.signal_names    = sig_names;
    results.zscores         = zscores_combined;
    results.zscore_global   = zscores_global;
    results.zscore_grouped  = zscores_grouped;
    results.zscore_traces   = zscore_traces;
    results.suspicious      = suspicious;
    results.threshold       = threshold;
    results.num_flagged     = length(suspicious);

    fprintf('\n  zscore_detect complete.\n');
end

% ============================================================================
% Helper: Identify signal groups for grouped Z-score comparison
% Groups signals by their functional role (e.g., all "result" signals together)
% ============================================================================
function groups = identify_signal_groups(sig_names)
    groups = cell(length(sig_names), 1);
    for s = 1:length(sig_names)
        name = lower(sig_names{s});
        % Extract the signal leaf name (after last '.')
        parts = strsplit(name, '.');
        leaf = parts{end};

        % Group by leaf name (result, state, clk, etc.)
        if contains(leaf, 'result')
            groups{s} = 'result';
        elseif contains(leaf, 'state')
            groups{s} = 'state';
        elseif contains(leaf, 'round_key') || contains(leaf, 'key')
            groups{s} = 'key';
        elseif contains(leaf, 'ciphertext')
            groups{s} = 'ciphertext';
        elseif contains(leaf, 'trojan')
            groups{s} = 'trojan_internal';
        elseif contains(leaf, 'counter')
            groups{s} = 'counter';
        elseif contains(leaf, 'clk') || contains(leaf, 'rst')
            groups{s} = 'control';
        else
            groups{s} = 'other';
        end
    end
end

% ============================================================================
% Helper: Truncate long signal name for display
% ============================================================================
function s = truncate_name(name)
    % Remove common prefixes
    s = strrep(name, 'alu_tb.', '');
    s = strrep(s, 'aes_tb.', '');
    if length(s) > 30
        s = ['...' s(end-26:end)];
    end
end
