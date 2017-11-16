# frozen_string_literal: true
module KubernetesDeploy
  class Deployment < KubernetesResource
    TIMEOUT = 7.minutes

    def sync
      raw_json, _err, st = kubectl.run("get", type, @name, "--output=json")
      @found = st.success?

      if @found
        @deployment_data = JSON.parse(raw_json)
        @desired_replicas = @deployment_data["spec"]["replicas"].to_i
        @latest_rs = find_latest_rs
        @rollout_data = { "replicas" => 0 }.merge(@deployment_data["status"]
          .slice("replicas", "updatedReplicas", "availableReplicas", "unavailableReplicas"))
        @status = @rollout_data.map { |state_replicas, num| "#{num} #{state_replicas.chop.pluralize(num)}" }.join(", ")
        conditions = @deployment_data.fetch("status", {}).fetch("conditions", [])
        @progress = conditions.find { |condition| condition['type'] == 'Progressing' }
      else # reset
        @latest_rs = nil
        @rollout_data = { "replicas" => 0 }
        @status = nil
      end
    end

    def fetch_events
      own_events = super
      return own_events unless @latest_rs.present?
      own_events.merge(@latest_rs.fetch_events)
    end

    def fetch_logs
      return {} unless @latest_rs.present?
      @latest_rs.fetch_logs
    end

    def deploy_succeeded?
      return false unless @latest_rs

      if @partial_rollout_success.nil?
        @latest_rs.deploy_succeeded? &&
        @latest_rs.desired_replicas == @desired_replicas && # latest RS fully scaled up
        @rollout_data["updatedReplicas"].to_i == @desired_replicas &&
        @rollout_data["updatedReplicas"].to_i == @rollout_data["availableReplicas"].to_i
      else
        minimum_needed = minimum_updated_replicas_to_succeeded

        # confirm only lastest and 1 other running && updatedReplicas > desired && updates == availableReplicas?
        running_rs.size <= 2 &&
        @rollout_data["updatedReplicas"].to_i > minimum_needed &&
        @rollout_data["availableReplicas"].to_i > minimum_needed
      end
    end

    def deploy_failed?
      @latest_rs && @latest_rs.deploy_failed?
    end

    def failure_message
      @latest_rs&.failure_message
    end

    def timeout_message
      progress_seconds = @definition['spec']['progressDeadlineSeconds']
      if progress_seconds
        "Deploy timed out due to progressDeadlineSeconds of #{progress_seconds} seconds, "\
        " reason: #{@progress['reason']}\n"\
        "#{@latest_rs&.timeout_message}"
      else
        @latest_rs&.timeout_message
      end
    end

    def deploy_timed_out?
      @progress ? @progress["status"] == 'False' : super
    end

    def exists?
      @found
    end

    private

    def all_rs_data(matchLabels)
      label_string = matchLabels.map { |k, v| "#{k}=#{v}" }.join(",")
      raw_json, _err, st = kubectl.run("get", "replicasets", "--output=json", "--selector=#{label_string}")
      return {} unless st.success?

      JSON.parse(raw_json)["items"]
    end

    def running_rs
      all_rs_data(@deployment_data["spec"]["selector"]["matchLabels"]).select do |rs|
        rs["status"]["replicas"].to_i > 0
      end
    end

    def minimum_updated_replicas_to_succeeded
      desired = @desired_replicas

      if @partial_rollout_success == :dynamic
        deployMaxUnavailable = @deployment_data.dig("spec", "strategy", "rollingUpdate", "maxUnavailable")
        if deployMaxUnavailable =~ /%/
          desired *= (100 - deployMaxUnavailable.to_i) / 100.0
        else
          desired -= deployMaxUnavailable.to_i
        end
      else
        desired = @partial_rollout_success
      end

      desired.to_i
    end

    def find_latest_rs
      current_revision = @deployment_data["metadata"]["annotations"]["deployment.kubernetes.io/revision"]

      latest_rs_data = all_rs_data(@deployment_data["spec"]["selector"]["matchLabels"]).find do |rs|
        rs["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == @deployment_data["metadata"]["uid"] } &&
        rs["metadata"]["annotations"]["deployment.kubernetes.io/revision"] == current_revision
      end

      return unless latest_rs_data.present?

      rs = ReplicaSet.new(
        namespace: namespace,
        context: context,
        definition: latest_rs_data,
        logger: @logger,
        parent: "#{@name.capitalize} deployment",
        deploy_started: @deploy_started
      )
      rs.sync(latest_rs_data)
      rs
    end
  end
end
