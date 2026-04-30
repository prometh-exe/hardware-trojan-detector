% ============================================================================
% pca_engine.m — PCA-Based Trojan Detection via Toggle Vector Clustering
% Runs Principal Component Analysis on toggle count matrices from clean
% and Trojan designs. Plots 2D cluster separation and annotates outliers.
%
% Usage:
%   pca_results = pca_engine(parsed_vcd_data);
%   pca_results = pca_engine(parsed_vcd_data, 'NumComponents', 3);
%
% Output struct fields:
%   pca_results.scores          — [num_signals x num_components] PCA scores
%   pca_results.coeff           — PCA coefficient matrix (loadings)
%   pca_results.explained       — Variance explained per component (%)
%   pca_results.labels          — Signal classification labels
%   pca_results.outliers        — Indices of outlier signals
%   pca_results.silhouette_score — Cluster quality metric
% ============================================================================

function pca_results = pca_engine(vcd_data, varargin)

    fprintf('\n========================================\n');
    fprintf(' pca_engine: PCA Cluster Analysis\n');
    fprintf('========================================\n');

    % ---- Parse optional parameters ----
    p = inputParser;
    addParameter(p, 'NumComponents', 2);
    addParameter(p, 'OutlierThreshold', 2.0);  % Mahalanobis distance threshold
    addParameter(p, 'WindowSize', 50);           % Sliding window for feature extraction
    parse(p, varargin{:});

    n_components   = p.Results.NumComponents;
    outlier_thresh = p.Results.OutlierThreshold;
    win_size       = p.Results.WindowSize;

    % ---- Extract data ----
    sig_names   = vcd_data.signal_names;
    widths      = vcd_data.signal_widths;
    toggles     = vcd_data.toggle_matrix;  % [num_signals x num_ts]
    num_signals = length(sig_names);
    num_ts      = size(toggles, 2);

    fprintf('  Signals: %d, Timestamps: %d\n', num_signals, num_ts);

    % ---- Feature Engineering ----
    % Create a rich feature matrix from toggle vectors
    % Features per signal: windowed mean, std, max, skewness, kurtosis
    num_windows = floor(num_ts / win_size);
    if num_windows < 1
        num_windows = 1;
        win_size = num_ts;
    end

    % Normalize by width first
    norm_toggles = zeros(size(toggles));
    for s = 1:num_signals
        if widths(s) > 0
            norm_toggles(s, :) = toggles(s, :) / widths(s);
        end
    end

    % Build feature matrix: [num_signals x (num_windows * 5)]
    features = zeros(num_signals, num_windows * 5);
    for s = 1:num_signals
        for w = 1:num_windows
            ws = (w-1)*win_size + 1;
            we = min(w*win_size, num_ts);
            window_data = norm_toggles(s, ws:we);

            base_idx = (w-1)*5;
            features(s, base_idx + 1) = mean(window_data);
            features(s, base_idx + 2) = std(window_data);
            features(s, base_idx + 3) = max(window_data);
            if length(window_data) > 2
                features(s, base_idx + 4) = skewness(window_data);
                features(s, base_idx + 5) = kurtosis(window_data);
            else
                features(s, base_idx + 4) = 0;
                features(s, base_idx + 5) = 0;
            end
        end
    end

    % Handle NaN/Inf values
    features(isnan(features)) = 0;
    features(isinf(features)) = 0;

    % ---- Standardize features ----
    feat_mu  = mean(features, 1);
    feat_std = std(features, 0, 1);
    feat_std(feat_std == 0) = 1;  % Avoid division by zero
    features_std = (features - feat_mu) ./ feat_std;

    % ---- Run PCA ----
    fprintf('  Running PCA with %d components...\n', n_components);
    [coeff, scores, latent, ~, explained] = pca(features_std);

    % Limit to requested components
    if size(scores, 2) < n_components
        n_components = size(scores, 2);
    end
    scores_reduced = scores(:, 1:n_components);
    explained_used = explained(1:n_components);

    fprintf('  Variance explained: ');
    for c = 1:n_components
        fprintf('PC%d=%.1f%% ', c, explained_used(c));
    end
    fprintf('(Total: %.1f%%)\n', sum(explained_used));

    % ---- Classify signals ----
    labels = cell(num_signals, 1);
    label_ids = zeros(num_signals, 1);  % 1=clean, 2=trojan, 3=control, 4=other

    for s = 1:num_signals
        name = lower(sig_names{s});
        if contains(name, 'clk') || contains(name, 'rst')
            labels{s} = 'Control';
            label_ids(s) = 3;
        elseif contains(name, 'clean') && ~contains(name, 'trojan')
            labels{s} = 'Clean';
            label_ids(s) = 1;
        elseif contains(name, 'trojan') || contains(name, 'comb') || ...
               contains(name, 'seq') || contains(name, 'counter')
            labels{s} = 'Trojan';
            label_ids(s) = 2;
        else
            labels{s} = 'Other';
            label_ids(s) = 4;
        end
    end

    % ---- Detect outliers via Mahalanobis distance from clean centroid ----
    clean_idx = find(label_ids == 1);
    outlier_flags = false(num_signals, 1);
    mahal_dist = zeros(num_signals, 1);

    if length(clean_idx) >= 2 && n_components >= 2
        clean_scores = scores_reduced(clean_idx, :);
        clean_mu     = mean(clean_scores, 1);
        clean_cov    = cov(clean_scores);

        % Regularize covariance to prevent singularity
        clean_cov = clean_cov + eye(n_components) * 1e-6;

        for s = 1:num_signals
            diff = scores_reduced(s, :) - clean_mu;
            mahal_dist(s) = sqrt(diff / clean_cov * diff');
        end

        outlier_flags = mahal_dist > outlier_thresh;
    end

    outlier_indices = find(outlier_flags);

    % ---- Compute silhouette score ----
    sil_score = 0;
    valid_labels = label_ids(label_ids == 1 | label_ids == 2);
    valid_scores = scores_reduced(label_ids == 1 | label_ids == 2, :);

    if length(unique(valid_labels)) >= 2 && size(valid_scores, 1) > 2
        try
            sil_vals = silhouette(valid_scores, valid_labels);
            sil_score = mean(sil_vals);
        catch
            sil_score = 0;
        end
    end

    fprintf('  Silhouette score (clean vs trojan): %.3f\n', sil_score);
    fprintf('  Outliers detected: %d\n', length(outlier_indices));

    % ---- Visualization ----
    results_dir = 'results';
    if ~exist(results_dir, 'dir'), mkdir(results_dir); end

    % Plot 1: 2D PCA scatter plot with clusters
    figure('Position', [100, 100, 1200, 800], 'Visible', 'off');

    subplot(2,2,[1,3]);
    hold on;

    % Color map for categories
    colors = [0.2 0.6 0.3;    % Clean = green
              0.85 0.15 0.15;  % Trojan = red
              0.5 0.5 0.5;     % Control = gray
              0.4 0.4 0.8];    % Other = blue
    markers = {'o', 's', '^', 'd'};
    cat_names = {'Clean', 'Trojan', 'Control', 'Other'};

    for cat = 1:4
        idx = find(label_ids == cat);
        if ~isempty(idx)
            scatter(scores_reduced(idx, 1), scores_reduced(idx, min(2, n_components)), ...
                80, colors(cat, :), 'filled', markers{cat}, ...
                'MarkerEdgeColor', 'k', 'LineWidth', 0.5, ...
                'DisplayName', cat_names{cat});
        end
    end

    % Annotate outliers
    for k = 1:length(outlier_indices)
        oi = outlier_indices(k);
        short_name = strrep(strrep(sig_names{oi}, 'alu_tb.', ''), 'aes_tb.', '');
        text(scores_reduced(oi, 1) + 0.1, scores_reduced(oi, min(2, n_components)) + 0.1, ...
            short_name, 'FontSize', 7, 'Color', [0.7 0 0], 'FontWeight', 'bold');
    end

    % Draw clean cluster boundary (2σ ellipse)
    if length(clean_idx) >= 3 && n_components >= 2
        theta = linspace(0, 2*pi, 100);
        clean_scores2d = scores_reduced(clean_idx, 1:2);
        c_mu = mean(clean_scores2d, 1);
        c_cov = cov(clean_scores2d) + eye(2) * 1e-6;
        [V, D] = eig(c_cov);
        r = outlier_thresh * sqrt(diag(D));
        ellipse_pts = [r(1)*cos(theta); r(2)*sin(theta)];
        ellipse_rot = V * ellipse_pts;
        plot(ellipse_rot(1,:) + c_mu(1), ellipse_rot(2,:) + c_mu(2), ...
            '--', 'Color', [0.2 0.6 0.3 0.5], 'LineWidth', 1.5, ...
            'DisplayName', 'Clean boundary');
    end

    xlabel(sprintf('PC1 (%.1f%% variance)', explained_used(1)));
    if n_components >= 2
        ylabel(sprintf('PC2 (%.1f%% variance)', explained_used(2)));
    end
    title('PCA Cluster Separation: Clean vs Trojan');
    legend('Location', 'best');
    grid on;
    hold off;

    % Plot 2: Scree plot (variance explained)
    subplot(2,2,2);
    n_show = min(10, length(explained));
    bar(1:n_show, explained(1:n_show), 'FaceColor', [0.3 0.5 0.8]);
    hold on;
    plot(1:n_show, cumsum(explained(1:n_show)), 'r-o', 'LineWidth', 2, 'MarkerSize', 6);
    xlabel('Principal Component');
    ylabel('Variance Explained (%)');
    title('Scree Plot');
    legend('Individual', 'Cumulative', 'Location', 'east');
    grid on;

    % Plot 3: Mahalanobis distance bar chart
    subplot(2,2,4);
    bar_c = zeros(num_signals, 3);
    for s = 1:num_signals
        if outlier_flags(s)
            bar_c(s, :) = [0.85 0.15 0.15];
        else
            bar_c(s, :) = [0.3 0.6 0.85];
        end
    end
    b = bar(mahal_dist);
    b.FaceColor = 'flat';
    b.CData = bar_c;
    hold on;
    yline(outlier_thresh, '--r', sprintf('Threshold=%.1f', outlier_thresh), 'LineWidth', 1.5);
    ylabel('Mahalanobis Distance');
    title('Distance from Clean Centroid');
    short_names = cellfun(@(s) strrep(strrep(s, 'alu_tb.', ''), 'aes_tb.', ''), ...
        sig_names, 'UniformOutput', false);
    set(gca, 'XTick', 1:num_signals, 'XTickLabel', short_names);
    xtickangle(55);
    set(gca, 'FontSize', 7);
    grid on;

    sgtitle('PCA-Based Hardware Trojan Detection', 'FontSize', 14, 'FontWeight', 'bold');
    saveas(gcf, fullfile(results_dir, 'pca_clusters.png'));
    fprintf('  Saved: %s\n', fullfile(results_dir, 'pca_clusters.png'));

    % ---- Print Results ----
    fprintf('\n  PCA Outlier Analysis:\n');
    fprintf('  %-50s  Label      Mahal.Dist  Outlier?\n', 'Signal');
    fprintf('  %s\n', repmat('-', 1, 85));

    [~, sort_idx] = sort(mahal_dist, 'descend');
    for k = 1:min(15, num_signals)
        idx = sort_idx(k);
        flag = '';
        if outlier_flags(idx), flag = ' *** OUTLIER ***'; end
        fprintf('  %-50s  %-8s   %7.3f    %s\n', ...
            sig_names{idx}, labels{idx}, mahal_dist(idx), flag);
    end

    % ---- Assemble output ----
    pca_results.scores           = scores_reduced;
    pca_results.coeff            = coeff(:, 1:n_components);
    pca_results.explained        = explained_used;
    pca_results.labels           = labels;
    pca_results.label_ids        = label_ids;
    pca_results.outliers         = outlier_indices;
    pca_results.outlier_flags    = outlier_flags;
    pca_results.mahal_dist       = mahal_dist;
    pca_results.silhouette_score = sil_score;
    pca_results.features         = features_std;

    fprintf('\n  pca_engine complete.\n');
end
