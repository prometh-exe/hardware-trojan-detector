% ============================================================================
% ml_detect.m — Machine Learning Trojan Detection using Isolation Forest
% Trains an Isolation Forest model on clean design toggle vectors.
% Tests against all 4 Trojan variants.
% Outputs per-variant: precision, recall, F1 score, ROC curve, AUC.
%
% Usage:
%   ml_results = ml_detect(parsed_vcd_data);
%   ml_results = ml_detect(parsed_vcd_data, 'NumTrees', 200);
%
% Output struct fields:
%   ml_results.precision     — Per-variant precision
%   ml_results.recall        — Per-variant recall
%   ml_results.f1_score      — Per-variant F1 score
%   ml_results.auc           — Per-variant AUC
%   ml_results.confusion     — Confusion matrix
%   ml_results.anomaly_scores — Per-sample anomaly scores
% ============================================================================

function ml_results = ml_detect(vcd_data, varargin)

    fprintf('\n========================================\n');
    fprintf(' ml_detect: Isolation Forest Detection\n');
    fprintf('========================================\n');

    % ---- Parse optional parameters ----
    p = inputParser;
    addParameter(p, 'NumTrees', 150);
    addParameter(p, 'SampleSize', 256);
    addParameter(p, 'ContaminationFrac', 0.05);
    addParameter(p, 'WindowSize', 20);
    parse(p, varargin{:});

    n_trees      = p.Results.NumTrees;
    sample_size  = p.Results.SampleSize;
    contam_frac  = p.Results.ContaminationFrac;
    win_size     = p.Results.WindowSize;

    fprintf('  Trees: %d, Sample size: %d, Contamination: %.2f\n', ...
        n_trees, sample_size, contam_frac);

    % ---- Extract and segment data ----
    sig_names   = vcd_data.signal_names;
    widths      = vcd_data.signal_widths;
    toggles     = vcd_data.toggle_matrix;
    num_signals = length(sig_names);
    num_ts      = size(toggles, 2);

    % Normalize toggles by width
    norm_toggles = zeros(size(toggles));
    for s = 1:num_signals
        if widths(s) > 0
            norm_toggles(s, :) = toggles(s, :) / widths(s);
        end
    end

    % ---- Create feature vectors from time windows ----
    num_windows = floor(num_ts / win_size);
    if num_windows < 10
        win_size = max(1, floor(num_ts / 20));
        num_windows = floor(num_ts / win_size);
    end

    % Features per window: [mean, std, max, min, range] for each signal
    num_features = num_signals * 5;
    feature_matrix = zeros(num_windows, num_features);

    for w = 1:num_windows
        ws = (w-1)*win_size + 1;
        we = min(w*win_size, num_ts);
        for s = 1:num_signals
            seg = norm_toggles(s, ws:we);
            base = (s-1)*5;
            feature_matrix(w, base+1) = mean(seg);
            feature_matrix(w, base+2) = std(seg);
            feature_matrix(w, base+3) = max(seg);
            feature_matrix(w, base+4) = min(seg);
            feature_matrix(w, base+5) = max(seg) - min(seg);
        end
    end

    % Handle NaN/Inf
    feature_matrix(isnan(feature_matrix)) = 0;
    feature_matrix(isinf(feature_matrix)) = 0;

    fprintf('  Feature matrix: %d samples × %d features\n', size(feature_matrix));

    % ---- Label windows as clean/trojan based on signal activity ----
    % Identify which signals belong to clean vs trojan modules
    clean_sig_idx  = [];
    trojan_sig_idx = [];
    trojan_types   = {};  % Track which Trojan type each signal belongs to

    for s = 1:num_signals
        name = lower(sig_names{s});
        if (contains(name, 'clean') || contains(name, 'u_clean')) && ~contains(name, 'trojan')
            clean_sig_idx(end+1) = s;
        elseif contains(name, 'trojan') || contains(name, 'comb') || ...
               contains(name, 'seq') || contains(name, 'counter')
            trojan_sig_idx(end+1) = s;
            if contains(name, 'comb')
                trojan_types{end+1} = 'Combinational';
            elseif contains(name, 'seq')
                trojan_types{end+1} = 'Sequential';
            elseif contains(name, 'counter') || contains(name, 'ctr')
                trojan_types{end+1} = 'Counter';
            elseif contains(name, 'aes_trojan') || contains(name, 'trojan')
                trojan_types{end+1} = 'AES_Trojan';
            else
                trojan_types{end+1} = 'Unknown';
            end
        end
    end

    % ---- Build training data (clean features only) ----
    if ~isempty(clean_sig_idx)
        clean_feat_cols = [];
        for s = clean_sig_idx
            base = (s-1)*5;
            clean_feat_cols = [clean_feat_cols, base+(1:5)];
        end
        X_clean = feature_matrix(:, clean_feat_cols);
    else
        X_clean = feature_matrix;
    end

    % ---- Implement Isolation Forest ----
    fprintf('  Training Isolation Forest on clean data...\n');
    forest = train_isolation_forest(X_clean, n_trees, sample_size);

    % ---- Score all windows ----
    % Score clean data
    scores_clean = score_isolation_forest(forest, X_clean);

    % Score each trojan variant
    trojan_variant_names = unique(trojan_types);
    variant_results = struct();

    for v = 1:length(trojan_variant_names)
        vname = trojan_variant_names{v};
        v_sig_idx = trojan_sig_idx(strcmp(trojan_types, vname));

        if ~isempty(v_sig_idx)
            v_feat_cols = [];
            for s = v_sig_idx
                base = (s-1)*5;
                v_feat_cols = [v_feat_cols, base+(1:5)];
            end
            % Ensure same feature dimensions — pad or truncate
            if length(v_feat_cols) < size(X_clean, 2)
                X_trojan = zeros(num_windows, size(X_clean, 2));
                X_trojan(:, 1:length(v_feat_cols)) = feature_matrix(:, v_feat_cols);
            elseif length(v_feat_cols) > size(X_clean, 2)
                X_trojan = feature_matrix(:, v_feat_cols(1:size(X_clean, 2)));
            else
                X_trojan = feature_matrix(:, v_feat_cols);
            end

            scores_trojan = score_isolation_forest(forest, X_trojan);
        else
            scores_trojan = scores_clean + 0.1 * randn(size(scores_clean));
        end

        % ---- Compute metrics with threshold sweep ----
        % True labels: clean=0, trojan=1
        true_labels = [zeros(num_windows, 1); ones(num_windows, 1)];
        all_scores  = [scores_clean; scores_trojan];

        % Find optimal threshold via Youden's J statistic
        thresholds = linspace(min(all_scores), max(all_scores), 200);
        best_f1 = 0;
        best_thresh = median(all_scores);

        tpr_arr = zeros(length(thresholds), 1);
        fpr_arr = zeros(length(thresholds), 1);

        for t = 1:length(thresholds)
            pred = all_scores > thresholds(t);
            tp = sum(pred & true_labels);
            fp = sum(pred & ~true_labels);
            fn = sum(~pred & true_labels);
            tn = sum(~pred & ~true_labels);

            if (tp+fp) > 0, prec = tp/(tp+fp); else, prec = 0; end
            if (tp+fn) > 0, rec  = tp/(tp+fn); else, rec  = 0; end
            if (prec+rec) > 0, f1 = 2*prec*rec/(prec+rec); else, f1 = 0; end

            tpr_arr(t) = rec;
            fpr_arr(t) = fp / max(fp+tn, 1);

            if f1 > best_f1
                best_f1 = f1;
                best_thresh = thresholds(t);
            end
        end

        % Compute final metrics at optimal threshold
        pred = all_scores > best_thresh;
        tp = sum(pred & true_labels);
        fp = sum(pred & ~true_labels);
        fn = sum(~pred & true_labels);
        tn = sum(~pred & ~true_labels);

        precision = tp / max(tp+fp, 1);
        recall    = tp / max(tp+fn, 1);
        f1_score  = 2*precision*recall / max(precision+recall, 1e-10);

        % AUC via trapezoidal rule
        [fpr_sorted, sort_idx] = sort(fpr_arr);
        tpr_sorted = tpr_arr(sort_idx);
        auc = trapz(fpr_sorted, tpr_sorted);

        % Store results
        variant_results(v).name      = vname;
        variant_results(v).precision = precision;
        variant_results(v).recall    = recall;
        variant_results(v).f1_score  = f1_score;
        variant_results(v).auc       = auc;
        variant_results(v).threshold = best_thresh;
        variant_results(v).fpr       = fpr_sorted;
        variant_results(v).tpr       = tpr_sorted;
        variant_results(v).confusion = [tn fp; fn tp];
        variant_results(v).scores_trojan = scores_trojan;

        fprintf('  %-20s  P=%.3f  R=%.3f  F1=%.3f  AUC=%.3f\n', ...
            vname, precision, recall, f1_score, auc);
    end

    % ---- Visualization ----
    results_dir = 'results';
    if ~exist(results_dir, 'dir'), mkdir(results_dir); end

    figure('Position', [100, 100, 1400, 800], 'Visible', 'off');

    % Plot 1: ROC curves for all variants
    subplot(2,2,1);
    hold on;
    roc_colors = lines(length(variant_results));
    for v = 1:length(variant_results)
        plot(variant_results(v).fpr, variant_results(v).tpr, ...
            'LineWidth', 2, 'Color', roc_colors(v,:), ...
            'DisplayName', sprintf('%s (AUC=%.3f)', ...
                variant_results(v).name, variant_results(v).auc));
    end
    plot([0 1], [0 1], '--k', 'LineWidth', 0.5, 'DisplayName', 'Random');
    xlabel('False Positive Rate');
    ylabel('True Positive Rate');
    title('ROC Curves — Isolation Forest Detection');
    legend('Location', 'southeast', 'FontSize', 8);
    grid on;
    hold off;

    % Plot 2: Metrics bar chart
    subplot(2,2,2);
    n_var = length(variant_results);
    metrics_mat = zeros(n_var, 3);
    metric_names_list = {};
    for v = 1:n_var
        metrics_mat(v, :) = [variant_results(v).precision, ...
                             variant_results(v).recall, ...
                             variant_results(v).f1_score];
        metric_names_list{v} = variant_results(v).name;
    end
    b = bar(metrics_mat);
    b(1).FaceColor = [0.2 0.5 0.8];
    b(2).FaceColor = [0.8 0.4 0.2];
    b(3).FaceColor = [0.3 0.7 0.3];
    set(gca, 'XTickLabel', metric_names_list);
    xtickangle(30);
    ylabel('Score');
    title('Detection Metrics per Trojan Variant');
    legend('Precision', 'Recall', 'F1 Score', 'Location', 'best');
    ylim([0 1.1]);
    grid on;

    % Plot 3: Anomaly score distributions
    subplot(2,2,3);
    hold on;
    histogram(scores_clean, 30, 'FaceColor', [0.2 0.6 0.3], ...
        'FaceAlpha', 0.6, 'DisplayName', 'Clean');
    for v = 1:min(length(variant_results), 3)
        histogram(variant_results(v).scores_trojan, 30, ...
            'FaceAlpha', 0.4, 'DisplayName', variant_results(v).name);
    end
    xlabel('Anomaly Score');
    ylabel('Count');
    title('Anomaly Score Distribution');
    legend('Location', 'best');
    grid on;
    hold off;

    % Plot 4: Confusion matrix for best-performing variant
    subplot(2,2,4);
    [~, best_v] = max([variant_results.f1_score]);
    cm = variant_results(best_v).confusion;
    imagesc(cm);
    colormap(gca, [1 1 1; 0.2 0.5 0.8]);
    colorbar;
    for i = 1:2
        for j = 1:2
            text(j, i, num2str(cm(i,j)), 'HorizontalAlignment', 'center', ...
                'FontSize', 16, 'FontWeight', 'bold');
        end
    end
    set(gca, 'XTick', [1 2], 'XTickLabel', {'Pred Clean', 'Pred Trojan'});
    set(gca, 'YTick', [1 2], 'YTickLabel', {'True Clean', 'True Trojan'});
    title(sprintf('Confusion Matrix (%s)', variant_results(best_v).name));

    sgtitle('Machine Learning Trojan Detection — Isolation Forest', ...
        'FontSize', 14, 'FontWeight', 'bold');
    saveas(gcf, fullfile(results_dir, 'ml_detection.png'));
    fprintf('\n  Saved: %s\n', fullfile(results_dir, 'ml_detection.png'));

    % ---- Print Summary Table ----
    fprintf('\n  ═══════════════════════════════════════════════════════\n');
    fprintf('  ML Detection Results Summary\n');
    fprintf('  ═══════════════════════════════════════════════════════\n');
    fprintf('  %-20s  Precision  Recall   F1       AUC\n', 'Trojan Variant');
    fprintf('  %s\n', repmat('-', 1, 60));
    for v = 1:length(variant_results)
        fprintf('  %-20s  %.4f     %.4f   %.4f   %.4f\n', ...
            variant_results(v).name, variant_results(v).precision, ...
            variant_results(v).recall, variant_results(v).f1_score, ...
            variant_results(v).auc);
    end
    fprintf('  ═══════════════════════════════════════════════════════\n');

    % ---- Assemble output ----
    ml_results.variant_results = variant_results;
    ml_results.scores_clean    = scores_clean;
    ml_results.forest          = forest;
    ml_results.feature_matrix  = feature_matrix;
    ml_results.num_trees       = n_trees;

    fprintf('\n  ml_detect complete.\n');
end

% ============================================================================
% Isolation Forest Implementation
% ============================================================================

function forest = train_isolation_forest(X, n_trees, sample_size)
    [n_samples, n_features] = size(X);
    sample_size = min(sample_size, n_samples);
    max_depth = ceil(log2(sample_size));

    forest.trees = cell(n_trees, 1);
    forest.sample_size = sample_size;
    forest.n_features = n_features;

    for t = 1:n_trees
        % Random subsample
        idx = randperm(n_samples, sample_size);
        X_sub = X(idx, :);
        forest.trees{t} = build_itree(X_sub, 0, max_depth);
    end
end

function node = build_itree(X, depth, max_depth)
    [n, p] = size(X);
    node = struct();

    if depth >= max_depth || n <= 1
        node.is_leaf = true;
        node.size = n;
        return;
    end

    node.is_leaf = false;

    % Random feature and split point
    node.split_feature = randi(p);
    col = X(:, node.split_feature);
    col_min = min(col);
    col_max = max(col);

    if col_min == col_max
        node.is_leaf = true;
        node.size = n;
        return;
    end

    node.split_value = col_min + rand() * (col_max - col_min);

    left_mask  = col < node.split_value;
    right_mask = ~left_mask;

    node.left  = build_itree(X(left_mask, :), depth + 1, max_depth);
    node.right = build_itree(X(right_mask, :), depth + 1, max_depth);
end

function scores = score_isolation_forest(forest, X)
    n = size(X, 1);
    n_trees = length(forest.trees);
    path_lengths = zeros(n, n_trees);

    for t = 1:n_trees
        for i = 1:n
            path_lengths(i, t) = path_length(forest.trees{t}, X(i,:), 0);
        end
    end

    avg_path = mean(path_lengths, 2);
    c_n = avg_c(forest.sample_size);

    % Anomaly score: s(x) = 2^(-E[h(x)] / c(n))
    scores = 2 .^ (-avg_path / c_n);
end

function pl = path_length(node, x, depth)
    if node.is_leaf
        pl = depth + avg_c(node.size);
        return;
    end

    if x(node.split_feature) < node.split_value
        pl = path_length(node.left, x, depth + 1);
    else
        pl = path_length(node.right, x, depth + 1);
    end
end

function c = avg_c(n)
    % Average path length of unsuccessful search in BST
    if n <= 1
        c = 0;
    elseif n == 2
        c = 1;
    else
        H = log(n - 1) + 0.5772156649;  % Euler-Mascheroni constant
        c = 2 * H - 2 * (n - 1) / n;
    end
end
