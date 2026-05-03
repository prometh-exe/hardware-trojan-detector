% ============================================================================
% trojan_dashboard.m — Interactive Trojan Detection Dashboard
% Built using MATLAB programmatic App Designer pattern (uifigure).
%
% Features:
%   - VCD file upload via file picker (Clean + Trojan)
%   - Dropdown to select analysis type
%   - Interactive plots: Bar Chart, Heat Map, Scatter, Timeline, Red Flags
%   - Single button triggers report_gen.m and exports PDF
%
% Usage:
%   trojan_dashboard        % Launch the dashboard
% ============================================================================

function trojan_dashboard()
    app = create_app();
end

function app = create_app()
    % ---- Main Figure ----
    app.fig = uifigure('Name', 'Trojan Detection Dashboard', ...
        'Position', [80 80 1280 780], ...
        'Color', [0.12 0.13 0.16], 'Resize', 'on');

    % ---- Storage ----
    app.clean_data  = [];
    app.trojan_data = [];
    app.results     = struct();

    % ============================================================
    % LEFT PANEL — Controls
    % ============================================================
    app.panel_ctrl = uipanel(app.fig, 'Title', 'Controls', ...
        'Position', [15 15 260 750], ...
        'BackgroundColor', [0.16 0.17 0.21], ...
        'ForegroundColor', [0.85 0.85 0.9], ...
        'FontSize', 14, 'FontWeight', 'bold');

    y = 690;
    % ---- Upload Section ----
    uilabel(app.panel_ctrl, 'Text', 'Upload VCD Files', ...
        'Position', [15 y 220 22], 'FontColor', [0.7 0.8 1], ...
        'FontSize', 13, 'FontWeight', 'bold');
    y = y - 35;

    app.btn_clean = uibutton(app.panel_ctrl, 'Text', 'Upload Clean VCD', ...
        'Position', [15 y 220 32], ...
        'BackgroundColor', [0.22 0.55 0.35], 'FontColor', 'w', ...
        'FontSize', 11, 'ButtonPushedFcn', @(~,~) upload_vcd(app, 'clean'));
    y = y - 38;

    app.lbl_clean = uilabel(app.panel_ctrl, 'Text', 'No file loaded', ...
        'Position', [15 y 220 18], 'FontColor', [0.5 0.5 0.5], 'FontSize', 9);
    y = y - 30;

    app.btn_trojan = uibutton(app.panel_ctrl, 'Text', 'Upload Trojan VCD', ...
        'Position', [15 y 220 32], ...
        'BackgroundColor', [0.7 0.2 0.2], 'FontColor', 'w', ...
        'FontSize', 11, 'ButtonPushedFcn', @(~,~) upload_vcd(app, 'trojan'));
    y = y - 38;

    app.lbl_trojan = uilabel(app.panel_ctrl, 'Text', 'No file loaded', ...
        'Position', [15 y 220 18], 'FontColor', [0.5 0.5 0.5], 'FontSize', 9);
    y = y - 40;

    % ---- Analysis Dropdown ----
    uilabel(app.panel_ctrl, 'Text', 'Select Analysis', ...
        'Position', [15 y 220 22], 'FontColor', [0.7 0.8 1], ...
        'FontSize', 13, 'FontWeight', 'bold');
    y = y - 32;

    app.dropdown = uidropdown(app.panel_ctrl, ...
        'Items', {'Toggle Comparison', 'Power Deviation', ...
                  'PCA Clusters', 'Anomaly Scores', 'Suspicious Signals'}, ...
        'Position', [15 y 220 30], ...
        'BackgroundColor', [0.22 0.24 0.30], 'FontColor', 'w', ...
        'FontSize', 11, 'ValueChangedFcn', @(~,~) run_analysis(app));
    y = y - 45;

    % ---- Run Button ----
    app.btn_run = uibutton(app.panel_ctrl, 'Text', 'Run Analysis', ...
        'Position', [15 y 220 38], ...
        'BackgroundColor', [0.25 0.45 0.85], 'FontColor', 'w', ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) run_analysis(app));
    y = y - 55;

    % ---- Generate Report Button ----
    app.btn_report = uibutton(app.panel_ctrl, 'Text', 'Generate PDF Report', ...
        'Position', [15 y 220 38], ...
        'BackgroundColor', [0.6 0.3 0.7], 'FontColor', 'w', ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) generate_report(app));
    y = y - 55;

    % ---- Status ----
    uilabel(app.panel_ctrl, 'Text', 'Status', ...
        'Position', [15 y 220 22], 'FontColor', [0.7 0.8 1], ...
        'FontSize', 13, 'FontWeight', 'bold');
    y = y - 25;

    app.lbl_status = uilabel(app.panel_ctrl, 'Text', 'Ready. Upload VCD files to begin.', ...
        'Position', [15 y 220 80], 'FontColor', [0.6 0.7 0.6], ...
        'FontSize', 10, 'WordWrap', 'on', 'VerticalAlignment', 'top');

    % ---- Info at bottom ----
    uilabel(app.panel_ctrl, 'Text', 'Hardware Security Framework v1.0', ...
        'Position', [15 15 220 18], 'FontColor', [0.35 0.35 0.4], ...
        'FontSize', 9, 'HorizontalAlignment', 'center');

    % ============================================================
    % RIGHT PANEL — Plot Area
    % ============================================================
    app.panel_plot = uipanel(app.fig, 'Title', 'Analysis View', ...
        'Position', [290 15 975 750], ...
        'BackgroundColor', [0.14 0.15 0.19], ...
        'ForegroundColor', [0.85 0.85 0.9], ...
        'FontSize', 14, 'FontWeight', 'bold');

    app.ax_main = uiaxes(app.panel_plot, 'Position', [40 280 900 420], ...
        'BackgroundColor', [0.18 0.19 0.23], 'XColor', [0.7 0.7 0.7], ...
        'YColor', [0.7 0.7 0.7], 'Color', [0.18 0.19 0.23]);
    title(app.ax_main, 'Select an analysis to begin', 'Color', [0.7 0.8 1], 'FontSize', 14);

    app.ax_secondary = uiaxes(app.panel_plot, 'Position', [40 20 900 230], ...
        'BackgroundColor', [0.18 0.19 0.23], 'XColor', [0.7 0.7 0.7], ...
        'YColor', [0.7 0.7 0.7], 'Color', [0.18 0.19 0.23]);
    title(app.ax_secondary, '', 'Color', [0.7 0.8 1]);

    assignin('base', 'dashboard_app', app);
end

% ============================================================
% Upload VCD callback
% ============================================================
function upload_vcd(app, type)
    [file, path] = uigetfile({'*.vcd', 'VCD Files (*.vcd)'; '*.*', 'All Files'}, ...
        ['Select ' upper(type) ' VCD File']);
    if isequal(file, 0), return; end

    full_path = fullfile(path, file);
    app.lbl_status.Text = sprintf('Parsing %s...', file);
    drawnow;

    try
        data = parse_vcd(full_path);

        if strcmp(type, 'clean')
            app.clean_data = data;
            app.lbl_clean.Text = file;
            app.lbl_clean.FontColor = [0.3 0.8 0.4];
        else
            app.trojan_data = data;
            app.lbl_trojan.Text = file;
            app.lbl_trojan.FontColor = [0.9 0.4 0.4];
        end

        app.lbl_status.Text = sprintf('%s loaded: %d signals, %d timestamps', ...
            upper(type), length(data.signal_names), length(data.timestamps));
        app.lbl_status.FontColor = [0.4 0.8 0.5];
    catch e
        app.lbl_status.Text = sprintf('Error: %s', e.message);
        app.lbl_status.FontColor = [0.9 0.3 0.3];
    end
end

% ============================================================
% Run selected analysis
% ============================================================
function run_analysis(app)
    % Use available data (prefer loaded files, fallback to synthetic)
    if isempty(app.clean_data) && isempty(app.trojan_data)
        app.lbl_status.Text = 'No VCD loaded. Using synthetic demo data...';
        app.lbl_status.FontColor = [0.9 0.7 0.3];
        drawnow;
        app.clean_data  = parse_vcd('vcd/alu_all.vcd');
        app.trojan_data = app.clean_data;
    end

    data = app.clean_data;
    if isempty(data), data = app.trojan_data; end

    analysis = app.dropdown.Value;
    app.lbl_status.Text = sprintf('Running: %s...', analysis);
    app.lbl_status.FontColor = [0.5 0.7 1];
    drawnow;

    try
        switch analysis
            case 'Toggle Comparison'
                plot_toggle_comparison(app, data);
            case 'Power Deviation'
                plot_power_heatmap(app, data);
            case 'PCA Clusters'
                plot_pca_scatter(app, data);
            case 'Anomaly Scores'
                plot_anomaly_timeline(app, data);
            case 'Suspicious Signals'
                plot_suspicious_flags(app, data);
        end
        app.lbl_status.Text = sprintf('%s complete.', analysis);
        app.lbl_status.FontColor = [0.4 0.8 0.5];
    catch e
        app.lbl_status.Text = sprintf('Error: %s', e.message);
        app.lbl_status.FontColor = [0.9 0.3 0.3];
    end
end

% ============================================================
% Plot: Toggle Comparison (Bar Chart)
% ============================================================
function plot_toggle_comparison(app, data)
    cla(app.ax_main); cla(app.ax_secondary);

    names  = data.signal_names;
    totals = data.total_toggles;
    n = length(names);

    % Color by type
    colors = zeros(n, 3);
    for s = 1:n
        nm = lower(names{s});
        if contains(nm, 'trojan') || contains(nm, 'comb') || ...
           contains(nm, 'seq') || contains(nm, 'counter')
            colors(s,:) = [0.85 0.2 0.2];
        elseif contains(nm, 'clean')
            colors(s,:) = [0.2 0.7 0.3];
        else
            colors(s,:) = [0.4 0.5 0.7];
        end
    end

    b = bar(app.ax_main, totals);
    b.FaceColor = 'flat';
    b.CData = colors;
    b.EdgeColor = 'none';

    short = cellfun(@(s) strrep(strrep(s,'alu_tb.',''),'aes_tb.',''), names, 'UniformOutput', false);
    app.ax_main.XTick = 1:n;
    app.ax_main.XTickLabel = short;
    app.ax_main.XTickLabelRotation = 50;
    app.ax_main.FontSize = 7;
    title(app.ax_main, 'Toggle Comparison: Total Switching Activity', ...
        'Color', [0.8 0.85 1], 'FontSize', 13);
    ylabel(app.ax_main, 'Total Toggles', 'Color', [0.7 0.7 0.7]);
    app.ax_main.GridColor = [0.3 0.3 0.3]; grid(app.ax_main, 'on');

    % Secondary: normalized per-width
    norm_totals = totals ./ max(data.signal_widths(:), 1);
    b2 = bar(app.ax_secondary, norm_totals);
    b2.FaceColor = 'flat'; b2.CData = colors; b2.EdgeColor = 'none';
    app.ax_secondary.XTick = 1:n;
    app.ax_secondary.XTickLabel = short;
    app.ax_secondary.XTickLabelRotation = 50;
    app.ax_secondary.FontSize = 7;
    title(app.ax_secondary, 'Width-Normalized Toggle Activity', ...
        'Color', [0.8 0.85 1], 'FontSize', 11);
    ylabel(app.ax_secondary, 'Toggles / Bit', 'Color', [0.7 0.7 0.7]);
    grid(app.ax_secondary, 'on');
end

% ============================================================
% Plot: Power Deviation (Heat Map)
% ============================================================
function plot_power_heatmap(app, data)
    cla(app.ax_main); cla(app.ax_secondary);

    pwr = power_model(data);
    app.results.power = pwr;

    % Heatmap of power traces (top 12 signals)
    [~, idx] = sort(pwr.power_per_signal, 'descend');
    show_idx = idx(1:min(12, length(idx)));
    traces = pwr.power_traces(show_idx, :);
    num_ts = size(traces, 2);
    ds = max(1, floor(num_ts / 500));
    traces_ds = traces(:, 1:ds:end);

    imagesc(app.ax_main, traces_ds);
    colormap(app.ax_main, hot);
    colorbar(app.ax_main);
    short = cellfun(@(s) strrep(strrep(s,'alu_tb.',''),'aes_tb.',''), ...
        pwr.signal_names(show_idx), 'UniformOutput', false);
    app.ax_main.YTick = 1:length(show_idx);
    app.ax_main.YTickLabel = short;
    app.ax_main.FontSize = 8;
    title(app.ax_main, 'Power Deviation Heatmap (mW)', ...
        'Color', [0.8 0.85 1], 'FontSize', 13);
    xlabel(app.ax_main, 'Time Step', 'Color', [0.7 0.7 0.7]);

    % Secondary: total power bar
    n = length(pwr.signal_names);
    bar_c = zeros(n, 3);
    for s = 1:n
        if pwr.power_deviation(s) > 1e-6
            bar_c(s,:) = [0.85 0.2 0.2];
        else
            bar_c(s,:) = [0.3 0.6 0.8];
        end
    end
    b = bar(app.ax_secondary, pwr.power_per_signal * 1000); % uW
    b.FaceColor = 'flat'; b.CData = bar_c; b.EdgeColor = 'none';
    title(app.ax_secondary, 'Average Power per Signal (μW)', ...
        'Color', [0.8 0.85 1], 'FontSize', 11);
    ylabel(app.ax_secondary, 'Power (μW)', 'Color', [0.7 0.7 0.7]);
    grid(app.ax_secondary, 'on');
end

% ============================================================
% Plot: PCA Clusters (Scatter)
% ============================================================
function plot_pca_scatter(app, data)
    cla(app.ax_main); cla(app.ax_secondary);

    pca_r = pca_engine(data);
    app.results.pca = pca_r;

    scores = pca_r.scores;
    labels = pca_r.label_ids;
    n = size(scores, 1);
    nc = min(2, size(scores, 2));

    colors_map = [0.2 0.7 0.3; 0.85 0.15 0.15; 0.5 0.5 0.5; 0.4 0.4 0.8];
    cat_names = {'Clean', 'Trojan', 'Control', 'Other'};

    hold(app.ax_main, 'on');
    for cat = 1:4
        idx = find(labels == cat);
        if ~isempty(idx) && nc >= 2
            scatter(app.ax_main, scores(idx,1), scores(idx,2), 70, ...
                colors_map(cat,:), 'filled', 'MarkerEdgeColor', [0.3 0.3 0.3]);
        end
    end
    hold(app.ax_main, 'off');

    legend(app.ax_main, cat_names(unique(labels)), 'TextColor', [0.8 0.8 0.8], ...
        'Color', [0.2 0.2 0.25], 'Location', 'best');
    title(app.ax_main, sprintf('PCA Clusters (%.1f%% + %.1f%% variance)', ...
        pca_r.explained(1), pca_r.explained(min(2,length(pca_r.explained)))), ...
        'Color', [0.8 0.85 1], 'FontSize', 13);
    xlabel(app.ax_main, 'PC1', 'Color', [0.7 0.7 0.7]);
    ylabel(app.ax_main, 'PC2', 'Color', [0.7 0.7 0.7]);
    grid(app.ax_main, 'on');

    % Mahalanobis distances
    bar_c = zeros(n, 3);
    for s = 1:n
        if pca_r.outlier_flags(s), bar_c(s,:)=[0.85 0.15 0.15];
        else, bar_c(s,:)=[0.3 0.55 0.8]; end
    end
    b = bar(app.ax_secondary, pca_r.mahal_dist);
    b.FaceColor = 'flat'; b.CData = bar_c; b.EdgeColor = 'none';
    title(app.ax_secondary, 'Mahalanobis Distance from Clean Centroid', ...
        'Color', [0.8 0.85 1], 'FontSize', 11);
    ylabel(app.ax_secondary, 'Distance', 'Color', [0.7 0.7 0.7]);
    grid(app.ax_secondary, 'on');
end

% ============================================================
% Plot: Anomaly Scores (Timeline)
% ============================================================
function plot_anomaly_timeline(app, data)
    cla(app.ax_main); cla(app.ax_secondary);

    zr = zscore_detect(data);
    app.results.zscore = zr;

    % Timeline: Z-score traces for top signals
    n_sig = length(zr.signal_names);
    [~, top_idx] = sort(abs(zr.zscores), 'descend');
    show_n = min(5, n_sig);
    show_idx = top_idx(1:show_n);

    colors = lines(show_n);
    hold(app.ax_main, 'on');
    num_ts = size(zr.zscore_traces, 2);
    ds = max(1, floor(num_ts / 600));
    t_ds = 1:ds:num_ts;

    for k = 1:show_n
        s = show_idx(k);
        trace = zr.zscore_traces(s, 1:ds:end);
        plot(app.ax_main, t_ds, trace, 'Color', colors(k,:), 'LineWidth', 1.2);
    end
    yline(app.ax_main, zr.threshold, '--r', 'LineWidth', 1.5);
    yline(app.ax_main, -zr.threshold, '--r', 'LineWidth', 1.5);
    hold(app.ax_main, 'off');

    short = cellfun(@(s) strrep(strrep(s,'alu_tb.',''),'aes_tb.',''), ...
        zr.signal_names(show_idx), 'UniformOutput', false);
    legend(app.ax_main, [short; {sprintf('±%.1fσ', zr.threshold)}], ...
        'TextColor', [0.8 0.8 0.8], 'Color', [0.2 0.2 0.25], ...
        'Location', 'best', 'FontSize', 7);
    title(app.ax_main, 'Anomaly Score Timeline (Sliding-Window Z-Score)', ...
        'Color', [0.8 0.85 1], 'FontSize', 13);
    xlabel(app.ax_main, 'Time Step', 'Color', [0.7 0.7 0.7]);
    ylabel(app.ax_main, 'Z-Score', 'Color', [0.7 0.7 0.7]);
    grid(app.ax_main, 'on');

    % Global Z-scores bar
    bar_c = zeros(n_sig, 3);
    for s = 1:n_sig
        if abs(zr.zscores(s)) > zr.threshold
            bar_c(s,:) = [0.85 0.15 0.15];
        else
            bar_c(s,:) = [0.3 0.55 0.8];
        end
    end
    b = bar(app.ax_secondary, zr.zscores);
    b.FaceColor = 'flat'; b.CData = bar_c; b.EdgeColor = 'none';
    hold(app.ax_secondary, 'on');
    yline(app.ax_secondary, zr.threshold, '--r');
    yline(app.ax_secondary, -zr.threshold, '--r');
    hold(app.ax_secondary, 'off');
    title(app.ax_secondary, 'Global Z-Scores per Signal', ...
        'Color', [0.8 0.85 1], 'FontSize', 11);
    grid(app.ax_secondary, 'on');
end

% ============================================================
% Plot: Suspicious Signals (Red Flags)
% ============================================================
function plot_suspicious_flags(app, data)
    cla(app.ax_main); cla(app.ax_secondary);

    zr = zscore_detect(data);
    app.results.zscore = zr;

    if isempty(zr.suspicious)
        text(app.ax_main, 0.5, 0.5, 'No suspicious signals detected', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center', ...
            'FontSize', 16, 'Color', [0.4 0.8 0.4]);
        title(app.ax_main, 'Suspicious Signal Report', ...
            'Color', [0.8 0.85 1], 'FontSize', 13);
        return;
    end

    n = length(zr.suspicious);
    names_s  = cell(n, 1);
    zvals    = zeros(n, 1);
    toggles_s = zeros(n, 1);
    for k = 1:n
        names_s{k}   = strrep(strrep(zr.suspicious(k).name, 'alu_tb.',''), 'aes_tb.','');
        zvals(k)     = abs(zr.suspicious(k).zscore);
        toggles_s(k) = zr.suspicious(k).total_toggles;
    end

    % Red flag bar chart
    barh(app.ax_main, zvals, 'FaceColor', [0.85 0.15 0.15], 'EdgeColor', 'none');
    hold(app.ax_main, 'on');
    xline(app.ax_main, zr.threshold, '--', 'Color', [1 0.8 0], 'LineWidth', 1.5);
    hold(app.ax_main, 'off');
    app.ax_main.YTick = 1:n;
    app.ax_main.YTickLabel = names_s;
    app.ax_main.FontSize = 8;
    title(app.ax_main, 'SUSPICIOUS SIGNALS — Red Flags', ...
        'Color', [1 0.3 0.3], 'FontSize', 14, 'FontWeight', 'bold');
    xlabel(app.ax_main, '|Z-Score|', 'Color', [0.7 0.7 0.7]);
    grid(app.ax_main, 'on');

    % Toggle counts for suspicious signals
    barh(app.ax_secondary, toggles_s, 'FaceColor', [0.9 0.5 0.1], 'EdgeColor', 'none');
    app.ax_secondary.YTick = 1:n;
    app.ax_secondary.YTickLabel = names_s;
    app.ax_secondary.FontSize = 8;
    title(app.ax_secondary, 'Toggle Counts of Flagged Signals', ...
        'Color', [0.8 0.85 1], 'FontSize', 11);
    xlabel(app.ax_secondary, 'Total Toggles', 'Color', [0.7 0.7 0.7]);
    grid(app.ax_secondary, 'on');
end

% ============================================================
% Generate PDF Report
% ============================================================
function generate_report(app)
    app.lbl_status.Text = 'Generating PDF report...';
    app.lbl_status.FontColor = [0.9 0.7 0.3];
    drawnow;

    try
        report_gen();
        app.lbl_status.Text = 'PDF report saved to results/ directory.';
        app.lbl_status.FontColor = [0.4 0.8 0.5];
    catch e
        app.lbl_status.Text = sprintf('Report error: %s', e.message);
        app.lbl_status.FontColor = [0.9 0.3 0.3];
    end
end
